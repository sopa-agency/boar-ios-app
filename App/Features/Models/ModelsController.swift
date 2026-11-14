import BoarAppleAI
import BoarCore
import BoarModels
import BoarRAG
import Foundation
import Observation
import os

/// The models and knowledge catalog (port of android `ModelsViewModel`, itself ModelCatalogScreen.tsx): download with
/// progress, speed and ETA, use, remove, and the Hugging Face search. Owned by `AppModel`, so a download keeps going
/// while the user is on another screen.
@MainActor
@Observable
final class ModelsController {
    /// One catalog row (CatalogRowState): downloading with progress, speed and ETA, or failed.
    struct Row: Equatable {
        var downloading = false
        var verifying = false
        var progress = 0.0
        var bytesWritten: Int64 = 0
        var speedBytesPerSec: Double?
        var etaSeconds: Double?
        var error: String?
        var indexing = false
    }

    private(set) var items: [CatalogAsset] = []
    private(set) var present: Set<String> = []
    private(set) var rows: [String: Row] = [:]
    private(set) var activeLlm: String?
    private(set) var activating: String?
    /// A short confirmation ("Qwen3 4B is answering now").
    var toast: String?

    // Hugging Face search (BrowseScreen): no request until the page opens.
    var hfQuery = ""
    private(set) var hfSize: HfQuery.Size = .any
    private(set) var hfSort: HfQuery.Sort = .trending
    private(set) var hfResults: [HfBrowser.Repo] = []
    private(set) var hfNext: String?
    private(set) var hfSearching = false
    private(set) var hfSearched = false
    var hfError: String?
    private(set) var hfOpenRepo: String?
    private(set) var hfFiles: [HfBrowser.GgufFile] = []
    private(set) var hfBusy = false
    /// The label of the model just added from Hugging Face.
    var hfAdded: String?

    @ObservationIgnored let services: BoarServices
    /// After the answering model changed (use, remove, Apple): the chat refreshes its header and suggestions.
    @ObservationIgnored var onModelChanged: (@MainActor () -> Void)?
    @ObservationIgnored private var jobs: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var searchToken = 0
    @ObservationIgnored private var repoToken = 0
    @ObservationIgnored private var refreshToken = 0
    private static let log = BoarLog.logger("models")

    init(services: BoarServices) {
        self.services = services
        refresh()
    }

    var totalRamBytes: Int64 { services.totalRamBytes }

    /// Answer models: the active one first, then the ones on the phone, then the rest, each in catalog order.
    var answerModels: [CatalogAsset] {
        items.filter { $0.kind == .llm }.enumerated().sorted { a, b in
            let ka = (a.element.id == activeLlm ? 0 : 1, present.contains(a.element.id) ? 0 : 1, a.offset)
            let kb = (b.element.id == activeLlm ? 0 : 1, present.contains(b.element.id) ? 0 : 1, b.offset)
            return ka < kb
        }.map(\.element)
    }

    var knowledgePacks: [CatalogAsset] { items.filter { $0.kind == .corpus } }
    var embeddingModel: CatalogAsset? { services.catalog.models.first { $0.kind == .embedding } }

    func isPresent(_ a: CatalogAsset) -> Bool { present.contains(a.id) }
    func isDiscovered(_ a: CatalogAsset) -> Bool { services.discovered().contains { $0.id == a.id } }

    /// The list itself too: a hidden model drops out once it's removed. The file checks run off the main actor (they
    /// block on disk); the newest call wins.
    func refresh() {
        refreshToken += 1
        let token = refreshToken
        Task {
            let scan = try? await services.background { s in
                let all = s.catalog.models
                return (all, Set(all.filter { s.assets.status($0).present }.map(\.id)), s.backend == .apple ? nil : s.activeModel()?.id)
            }
            guard let (all, onDisk, active) = scan, token == refreshToken else { return }
            present = onDisk
            items = all.filter { !$0.hidden || onDisk.contains($0.id) }
                .enumerated()
                .sorted { a, b in (Self.kindOrder(a.element.kind), a.offset) < (Self.kindOrder(b.element.kind), b.offset) }
                .map(\.element)
            activeLlm = active
        }
    }

    private static func kindOrder(_ k: AssetKind) -> Int {
        switch k {
        case .llm: 0
        case .embedding: 1
        case .corpus: 2
        }
    }

    // MARK: downloads

    func download(_ a: CatalogAsset) {
        if rows[a.id]?.downloading == true { return }
        rows[a.id] = Row(downloading: true)
        let services = services
        let throttle = Throttle(interval: 0.25)
        let meter = SpeedMeter()
        jobs[a.id] = Task {
            do {
                try await services.downloads.download(a, store: services.assets, filesDir: services.filesDir, catalog: services.catalog) { p in
                    let (speed, eta) = meter.sample(done: p.bytesDone, total: p.bytesTotal)
                    guard throttle.ready(force: p.verifying || p.bytesDone >= p.bytesTotal) else { return }
                    Task { @MainActor in
                        guard self.rows[a.id]?.downloading == true else { return }
                        self.rows[a.id]?.progress = p.bytesTotal > 0 ? Double(p.bytesDone) / Double(p.bytesTotal) : 0
                        self.rows[a.id]?.bytesWritten = p.bytesDone
                        self.rows[a.id]?.speedBytesPerSec = speed
                        self.rows[a.id]?.etaSeconds = eta
                        self.rows[a.id]?.verifying = p.verifying
                    }
                }
                rows[a.id] = Row()
                refresh()
                if a.kind == .corpus && a.format != "sqlite-pack" { await index(a) }
                if a.kind == .corpus { services.packs.reload() }
                onModelChanged?()
            } catch is CancellationError {
                // Cancelled by the user: the partial file and its resume data go too, so nothing is left half-downloaded.
                services.assets.delete(a)
                try? FileManager.default.removeItem(at: AppPaths.resumeDir.appending(path: "\(a.id).data"))
                rows[a.id] = Row()
            } catch {
                rows[a.id] = Row(error: DownloadErrorText.message(error))
            }
            jobs[a.id] = nil
            refresh()
        }
    }

    /// Stops a download and deletes what it wrote so far.
    func cancelDownload(_ a: CatalogAsset) {
        jobs[a.id]?.cancel()
    }

    /// A JSON corpus pack is searchable once indexed with the embedding model (as setup does).
    private func index(_ pack: CatalogAsset) async {
        rows[pack.id, default: Row()].indexing = true
        do {
            try await Task.detached(priority: .userInitiated) { [services] in try await KnowledgeIndexer.seedAll(services: services) }.value
        } catch {
            rows[pack.id, default: Row()].error = error.localizedDescription
        }
        rows[pack.id, default: Row()].indexing = false
    }

    // MARK: use / remove

    /// "Use": the model the chat answers with from now on, loaded right away.
    func use(_ a: CatalogAsset) {
        guard activating == nil, a.kind == .llm else { return }
        activating = a.id
        let services = services
        Task {
            services.settings.setActiveModelId("llm", a.id)
            // Picked again after it closed the app: the user's call (CR-2's confirmation).
            services.loadGuard.confirm(a.id)
            services.backend = .llama
            await services.host.unload()
            let loaded = await services.activeSession() != nil
            activating = nil
            toast = loaded ? String(localized: "Now answering with \(a.friendlyName)") : String(localized: "\(a.friendlyName) couldn't be loaded")
            refresh()
            onModelChanged?()
        }
    }

    /// Apple's on-device model answers from now on (when this iPhone has Apple Intelligence).
    func useApple() {
        guard activating == nil else { return }
        activating = "apple"
        let services = services
        Task {
            services.backend = .apple
            await services.host.unload()
            let loaded = await services.host.loadApple() != nil
            activating = nil
            toast = loaded ? String(localized: "Now answering with Apple Intelligence") : AppleModelAvailability.current.userMessage
            refresh()
            onModelChanged?()
        }
    }

    func remove(_ a: CatalogAsset) {
        let services = services
        let wasActive = a.id == activeLlm
        Task {
            if wasActive { await services.host.unload() }
            if a.kind == .corpus && a.format != "sqlite-pack" {
                _ = try? await services.background { try $0.knowledgeBase.deleteSeedChunksWithPrefix(SeedCorpus.chunkIdPrefix(a.id)) }
            }
            if a.kind == .corpus { services.packs.reload() }
            services.assets.delete(a)
            rows[a.id] = Row()
            toast = String(localized: "Deleted \(a.friendlyName)")
            refresh()
            onModelChanged?()
        }
    }

    /// A model added from Hugging Face but not downloaded leaves the list (the Expo app's ✕).
    func removeFromList(_ a: CatalogAsset) {
        let services = services
        let running = jobs[a.id]
        Task {
            // Wait for the download's own cleanup, so it can't run after the delete and bring the row back.
            running?.cancel()
            await running?.value
            services.assets.delete(a)
            services.removeDiscovered(a.id)
            rows[a.id] = nil
            refresh()
        }
    }

    // MARK: Hugging Face

    /// A new search with these filters: replaces the results; an older answer still running is dropped.
    /// The size filter as a bindable value: a new choice browses again.
    var hfSizeChoice: HfQuery.Size {
        get { hfSize }
        set { hfBrowse(size: newValue) }
    }

    /// The sort order as a bindable value: a new choice browses again.
    var hfSortChoice: HfQuery.Sort {
        get { hfSort }
        set { hfBrowse(sort: newValue) }
    }

    func hfBrowse(size: HfQuery.Size? = nil, sort: HfQuery.Sort? = nil) {
        if let size { hfSize = size }
        if let sort { hfSort = sort }
        searchToken += 1
        repoToken += 1
        hfSearching = true
        hfSearched = true
        hfError = nil
        hfResults = []
        hfNext = nil
        hfOpenRepo = nil
        hfFiles = []
        hfBusy = false
        hfAdded = nil
        fetchPage(HfQuery.searchUrl(hfQuery.trimmingCharacters(in: .whitespacesAndNewlines), size: hfSize, sort: hfSort), append: false)
    }

    /// The next page of the same search, at the end of the list.
    func hfMore() {
        guard let next = hfNext, !hfSearching else { return }
        hfSearching = true
        hfError = nil
        fetchPage(next, append: true)
    }

    private func fetchPage(_ url: String, append: Bool) {
        let token = searchToken
        Task {
            do {
                let page = try await HfBrowser.browse(url)
                guard token == searchToken else { return }
                var seen = Set<String>()
                hfResults = ((append ? hfResults : []) + page.repos).filter { seen.insert($0.id).inserted }
                hfNext = page.next
            } catch {
                guard token == searchToken else { return }
                hfError = error.localizedDescription
            }
            hfSearching = false
        }
    }

    /// Opens a repo's files (a second tap closes it); an older answer is dropped.
    func hfOpen(_ repo: String) {
        repoToken += 1
        let token = repoToken
        if hfOpenRepo == repo {
            hfOpenRepo = nil
            hfFiles = []
            hfBusy = false
            return
        }
        hfBusy = true
        hfError = nil
        hfOpenRepo = repo
        hfFiles = []
        Task {
            do {
                let files = try await HfBrowser.files(repo)
                guard token == repoToken else { return }
                hfFiles = files
            } catch {
                guard token == repoToken else { return }
                hfError = error.localizedDescription
            }
            hfBusy = false
        }
    }

    /// Adds the file to the model list as a downloadable model (not downloaded yet).
    func hfAdd(_ repo: String, _ file: HfBrowser.GgufFile) {
        do {
            let asset = try HfBrowser.toAsset(repoId: repo, file: file)
            services.addDiscovered(asset)
            let added = services.discovered().count
            services.vault.record { $0.hfModels = max($0.hfModels, added) }
            hfAdded = asset.label
            refresh()
        } catch {
            hfError = error.localizedDescription
        }
    }

    /// The catalog entry a file becomes once added (same id as `hfAdd` gives it), to show its download state in the search.
    func hfAsset(_ repo: String, _ file: HfBrowser.GgufFile) -> CatalogAsset? {
        try? HfBrowser.toAsset(repoId: repo, file: file)
    }

    /// Download from the search: adds the file to Models and starts its download right there.
    func hfDownload(_ repo: String, _ file: HfBrowser.GgufFile) {
        hfAdd(repo, file)
        if let asset = hfAsset(repo, file) { download(asset) }
    }

    /// Cancel from the search: stops the download and takes the model off the list again, so nothing half-added stays.
    func hfCancel(_ asset: CatalogAsset) {
        if hfAdded == asset.label { hfAdded = nil }
        removeFromList(asset)
    }
}

/// Download speed (smoothed, sampled once a second) and time left, from any thread (ModelsViewModel's EMA).
final class SpeedMeter: Sendable {
    private struct State {
        var lastAt = Date()
        var lastBytes: Int64 = -1
        var speed: Double?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func sample(done: Int64, total: Int64) -> (speed: Double?, eta: Double?) {
        state.withLock { s in
            let now = Date()
            if s.lastBytes < 0 {
                s.lastBytes = done
                s.lastAt = now
            }
            let dt = now.timeIntervalSince(s.lastAt)
            if dt >= 1 {
                let inst = Double(done - s.lastBytes) / dt
                s.speed = s.speed.map { $0 * 0.7 + inst * 0.3 } ?? inst
                s.lastAt = now
                s.lastBytes = done
            }
            let eta = s.speed.flatMap { $0 > 0 ? Double(total - done) / $0 : nil }
            return (s.speed, eta)
        }
    }
}

#if DEBUG
extension ModelsController {
    /// UI audit (`-uiScreen models-downloading`): the recommended model part-way down.
    func debugShowDownload() {
        guard let asset = services.catalog.byId("qwen3-4b-instruct-2507-q4km") else { return }
        rows[asset.id] = Row(downloading: true, progress: 0.43, bytesWritten: Int64(Double(asset.sizeBytes) * 0.43),
                             speedBytesPerSec: 6_200_000, etaSeconds: 214)
    }

    /// UI audit (`-uiScreen models-browse`): search results without the network.
    func debugShowBrowse(_ repos: [HfBrowser.Repo]) {
        hfResults = repos
        hfSearched = true
        hfNext = nil
    }
}
#endif

/// A failed download's text (android `UserErrors.downloadKey`): BOAR's own limit and a full phone read differently,
/// since the phone may have plenty of room when the limit is hit. Every cause has its own text: the engine's messages are
/// English and name the file, which the row already does.
enum DownloadErrorText {
    static func message(_ error: Error) -> String {
        guard let error = error as? AssetStore.DownloadError else {
            // No route, DNS, a dropped or timed-out connection (Kotlin's bare IOException).
            if error is URLError { return String(localized: "No connection to the download server. Check your connection and retry.") }
            return String(localized: "The download stopped. Retry.")
        }
        switch error {
        case .noSource: return String(localized: "Not available for download yet. Import the file instead.")
        case .offlineBuild: return String(localized: "This build of BOAR has no network access. Import the file instead.")
        case .storage(_, let refused?): return storage(refused)
        // A disk error while writing: no budget numbers to show.
        case .storage(_, nil): return String(localized: "This \(Platform.deviceNoun) doesn't have enough free space for the download. Free some space and retry.")
        case .sizeChanged: return String(localized: "The server now has a different file than this version of BOAR expects. Import the file or update the app.")
        case .paused: return String(localized: "The download paused (no data). Check your connection and try again.")
        case .checksum: return String(localized: "The file didn't match its checksum and was removed. Retry the download.")
        // 401/403: the file needs an account (a gated Hugging Face model): retrying won't help.
        case .http(_, let code) where code == 401 || code == 403:
            return String(localized: "This model needs a Hugging Face account and its license accepted. BOAR downloads without an account, so it can't get this one.")
        case .http: return String(localized: "The download server didn't answer. Retry later.")
        case .network: return String(localized: "No connection to the download server. Check your connection and retry.")
        }
    }

    private static func storage(_ refused: StorageBudget.Refused) -> String {
        func size(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file)) }
        let budget = size(refused.budgetBytes), used = size(refused.usedBytes), needed = size(refused.neededBytes)
        let device = Platform.deviceNoun
        switch refused.reason {
        case .disk:
            let free = refused.freeDiskBytes.map(size) ?? "?"
            return String(localized: "This \(device) has only \(free) free and the download needs \(needed). Free some space and retry.")
        case .budget where refused.downloadingBytes > 0:
            let downloading = size(refused.downloadingBytes)
            return String(localized: "BOAR's \(budget) storage limit is reached: BOAR stores \(used), with \(downloading) downloading. Remove a model or cancel a download. The \(device) itself may still have room.")
        case .budget:
            return String(localized: "BOAR's \(budget) storage limit is reached: BOAR already stores \(used). Remove a model first. The \(device) itself may still have room.")
        }
    }
}
