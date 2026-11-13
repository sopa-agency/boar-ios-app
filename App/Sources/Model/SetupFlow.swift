import BoarCore
import BoarLlama
import BoarModels
import BoarRAG
import Foundation
import Observation
import Synchronization

/// The two knowledge packages of setup (src/ui/flows/packages.ts): each is a catalog tier.
enum SetupPackage: String, CaseIterable, Identifiable, Sendable {
    case essential
    case encyclopedia

    var id: String { rawValue }
    var tierId: String { self == .essential ? "full" : "encyclopedia" }
    var title: String { self == .essential ? String(localized: "Essentials") : String(localized: "Encyclopedia") }
    var body: String {
        self == .essential
            ? String(localized: "Core topics for everyday questions")
            : String(localized: "Adds 50,000 Wikipedia article intros")
    }
}

/// One file of the install step, as its row shows it.
struct AssetProgress: Identifiable, Sendable {
    var asset: CatalogAsset
    var bytesDone: Int64 = 0
    var verifying = false
    var done = false
    var error: String?
    /// Not enough space: the step offers a smaller package.
    var storage = false

    var id: String { asset.id }
    var moving: Bool { !done && error == nil && (bytesDone > 0 || verifying) }
    var fraction: Double { done ? 1 : asset.sizeBytes > 0 ? min(max(Double(bytesDone) / Double(asset.sizeBytes), 0), 1) : 0 }
}

/// A package as its card shows it: what it adds, what is left to download, and whether it fits the free space.
struct PackagePlan: Identifiable, Sendable {
    var package: SetupPackage
    var assets: [CatalogAsset]
    var downloadBytes: Int64
    var installedBytes: Int64
    var shortfallBytes: Int64
    var id: SetupPackage { package }
}

enum IndexPhase: Sendable { case waiting, building, ready, error }

/// The first-run setup (port of android `SetupViewModel`, itself SetupWizardScreen.tsx): welcome with the phone's
/// numbers, the answer model (recommended by RAM), the knowledge package (recommended by free space), then the
/// downloads (background URLSession: resumable, verified, retried) and the search index, ending on a summary.
@MainActor
@Observable
final class SetupFlow {
    enum Step: Int, Sendable { case welcome = 1, model, knowledge, install }

    private(set) var step: Step = .welcome
    let totalRamBytes: Int64
    private(set) var freeDiskBytes: Int64 = -1
    private(set) var models: [CatalogAsset] = []
    private(set) var recommendedId: String?
    private(set) var chosenId: String?
    private(set) var plans: [PackagePlan] = []
    private(set) var recommendedPackage: SetupPackage?
    private(set) var package: SetupPackage = .essential
    private(set) var downloads: [AssetProgress] = []
    /// Measured download time left, once 5 s of bytes came in.
    private(set) var etaSeconds: Int?
    /// No byte for a minute while downloading: offer to restart the downloads.
    private(set) var stalled = false
    private(set) var indexPhase: IndexPhase = .waiting
    private(set) var indexDone = 0
    private(set) var indexTotal = 0
    private(set) var indexTitle = ""
    private(set) var indexEtaSeconds: Int?
    private(set) var indexError: String?
    /// Setup was in its install step when the process ended: the app opens on it.
    private(set) var unfinished = false
    /// Step 4's guide (SetupGuide): its pages, the one on screen, and whether the download's details show in its place.
    private(set) var pages: [SetupGuide.Page] = []
    private(set) var guidePage = 0
    private(set) var details = false

    @ObservationIgnored let services: BoarServices
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var stallWatch: Task<Void, Never>?
    @ObservationIgnored private var packageChosen = false
    @ObservationIgnored private var answerChosen = false
    @ObservationIgnored private var rateStart: (bytes: Int64, at: Date)?
    @ObservationIgnored private var lastMove = (bytes: Int64(0), at: Date())
    @ObservationIgnored private var indexStart: (done: Int, at: Date)?
    /// The newest `refreshPlans()`: an older scan that finishes later is dropped.
    @ObservationIgnored private var plansToken = 0
    private static let stallSeconds: TimeInterval = 60

    init(services: BoarServices) {
        self.services = services
        totalRamBytes = services.totalRamBytes
        // Only the built-in suggested models: models added from Hugging Face come in through Models.
        let added = Set(services.discovered().map(\.id))
        models = services.catalog.setupModels.filter { !added.contains($0.id) }
        let rec = BoarModels.SetupModel.recommended(services.catalog.answerModels, totalRamBytes: totalRamBytes)
        recommendedId = rec?.id
        chosenId = rec?.id
        pages = Self.guidePages(lockOn: Self.lockOn(services))
        restore()
        // Process killed in step 4: pick up there, once the plans settled the package. Files already in are skipped and
        // the index skips what it has.
        unfinished = step == .install
        let resume = unfinished
        Task {
            await updatePlans()
            if resume { install() }
        }
        watchStall()
    }

    var allPresent: Bool { !downloads.isEmpty && downloads.allSatisfy(\.done) }
    var failed: [AssetProgress] { downloads.filter { $0.error != nil } }
    /// Files are still coming in and nothing has failed.
    var transferring: Bool { !downloads.isEmpty && !allPresent && failed.isEmpty }
    var totalBytes: Int64 { downloads.reduce(0) { $0 + $1.asset.sizeBytes } }
    var doneBytes: Int64 { downloads.reduce(0) { $0 + ($1.done ? $1.asset.sizeBytes : $1.bytesDone) } }
    var finished: Bool { indexPhase == .ready }
    var chosenModel: CatalogAsset? { chosenId.flatMap(services.catalog.byId) }

    /// The RAM-fit verdict, the same one the Models screen shows.
    func fit(_ m: CatalogAsset) -> Compatibility { Compatibility.compute(sizeBytes: m.sizeBytes, deviceRamBytes: totalRamBytes) }
    func isCompact(_ m: CatalogAsset) -> Bool { m.answerTier == .compact }

    /// The guide's page on screen; Ready past the end.
    var page: SetupGuide.Page { pages.indices.contains(guidePage) ? pages[guidePage] : .ready }

    // MARK: navigation

    func next() { setStep(Step(rawValue: min(step.rawValue + 1, 3)) ?? .knowledge) }
    func back() { setStep(Step(rawValue: max(step.rawValue - 1, 1)) ?? .welcome) }

    private func setStep(_ s: Step) {
        step = s
        save()
    }

    func guideNext() { setGuide(guidePage + 1) }
    func guideBack() { setGuide(guidePage - 1) }
    func guideTo(_ p: SetupGuide.Page) { if let i = pages.firstIndex(of: p) { setGuide(i) } }
    func showDetails(_ on: Bool) { details = on }

    private func setGuide(_ i: Int) {
        guidePage = min(max(i, 0), max(pages.count - 1, 0))
        details = false
        save()
    }

    /// The lock page only when the lock was off as this setup started (a setup run again from Settings may find it on);
    /// iOS has no notification page. The files page comes in with setup's file import.
    private static func guidePages(lockOn: Bool) -> [SetupGuide.Page] {
        SetupGuide.pages(experimental: LabsBuild.experimental, pinSetBefore: lockOn, notifications: false).filter { $0 != .files }
    }

    private static func lockOn(_ services: BoarServices) -> Bool {
        services.settings.jsonValue(forKey: AppLock.settingsKey)?.boolValue ?? false
    }

    func choose(_ id: String) {
        answerChosen = true
        chosenId = id
        refreshPlans()
        save()
    }

    func choosePackage(_ p: SetupPackage) {
        packageChosen = true
        package = p
        save()
    }

    /// Settings → Recovery: the wizard from step 1 again.
    func restart() {
        job?.cancel()
        job = nil
        step = .welcome
        downloads = []
        indexPhase = .waiting
        indexError = nil
        stalled = false
        pages = Self.guidePages(lockOn: Self.lockOn(services))
        guidePage = 0
        details = false
        refreshPlans()
        save()
    }

    /// Setup is over (finished, or left from Settings): the next start doesn't resume it.
    func forget() {
        stallWatch?.cancel()
        try? FileManager.default.removeItem(at: AppPaths.setupProgress)
    }

    // MARK: packages

    /// The package's files: the required ones (search model), the chosen answer model and the tier's collections.
    private func assetsOf(_ p: SetupPackage) -> [CatalogAsset] {
        let catalog = services.catalog
        let chosen = chosenId.flatMap(catalog.byId)
        let packs = (catalog.tier(p.tierId)?.corpusPackIds ?? []).compactMap(catalog.byId)
        var seen = Set<String>()
        return (catalog.models.filter { $0.required && $0.kind != .llm } + (chosen.map { [$0] } ?? []) + packs).filter { seen.insert($0.id).inserted }
    }

    /// Sizes, free space and the recommendation (the biggest package that fits), recomputed when the choice changes.
    func refreshPlans() {
        Task { await updatePlans() }
    }

    /// `refreshPlans()` as a step to wait on. The free-space query and the file checks run off the main actor: they
    /// block on disk and on the system's cache-delete service (launch microhangs on the iPhone 13).
    private func updatePlans() async {
        plansToken += 1
        let token = plansToken
        let packages = SetupPackage.allCases.map { ($0, assetsOf($0)) }
        let wanted = packages.flatMap(\.1)
        let (free, present) = await diskScan(wanted)
        guard token == plansToken else { return }
        freeDiskBytes = free
        plans = packages.map { p, assets in
            let download = assets.filter { !present.contains($0.id) }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return PackagePlan(package: p, assets: assets, downloadBytes: download, installedBytes: assets.reduce(0) { $0 + $1.sizeBytes },
                               shortfallBytes: free >= 0 ? max(0, download - free) : 0)
        }
        let rec = (plans.last { $0.shortfallBytes == 0 } ?? plans.first)?.package
        recommendedPackage = rec
        if !packageChosen, let rec { package = rec }
    }

    /// Free bytes (-1 when unknown) and which of `assets` are on disk, read off the main actor.
    private func diskScan(_ assets: [CatalogAsset]) async -> (free: Int64, present: Set<String>) {
        let scan = try? await services.background { s in
            (DiskSpace.freeBytes(at: s.filesDir) ?? -1, Set(assets.filter { s.assets.status($0).present }.map(\.id)))
        }
        return scan ?? (-1, [])
    }

    /// The ids of `assets` on disk, read off the main actor.
    private func presentIds(_ assets: [CatalogAsset]) async -> Set<String> {
        (try? await services.background { s in Set(assets.filter { s.assets.status($0).present }.map(\.id)) }) ?? []
    }

    // MARK: install

    /// Step 3 → 4: downloads what is missing, then builds the index.
    func install() {
        if job != nil { return }
        let assets = assetsOf(package)
        if let id = chosenId { services.settings.setActiveModelId("llm", id) }
        job = Task {
            defer { self.job = nil }
            // The file checks run off the main actor; the rows show once they're known.
            let present = await presentIds(assets)
            if Task.isCancelled { return }
            let previous = downloads
            downloads = assets.map { a in
                if var p = previous.first(where: { $0.asset.id == a.id }) {
                    p.error = nil
                    p.storage = false
                    return p
                }
                return AssetProgress(asset: a, done: present.contains(a.id))
            }
            step = .install
            stalled = false
            save()
            rateStart = nil
            lastMove = (doneBytes, Date())
            for a in assets {
                if Task.isCancelled { return }
                if await presentIds([a]).contains(a.id) {
                    update(a.id) { $0.done = true; $0.bytesDone = a.sizeBytes }
                    continue
                }
                if await !fetch(a) { return }
            }
            await index()
        }
    }

    /// One file, with up to three quiet retries when the connection stalls (the bytes already in are kept).
    private func fetch(_ a: CatalogAsset) async -> Bool {
        var attempt = 0
        let throttle = Throttle(interval: 0.25)
        while true {
            do {
                try await services.downloads.download(a, store: services.assets, filesDir: services.filesDir, catalog: services.catalog) { p in
                    // At most 4 screen updates a second.
                    guard throttle.ready(force: p.verifying || p.bytesDone >= p.bytesTotal) else { return }
                    Task { @MainActor in
                        self.update(a.id) { $0.bytesDone = p.bytesDone; $0.verifying = p.verifying }
                        self.moved()
                    }
                }
                update(a.id) { $0.done = true; $0.bytesDone = a.sizeBytes; $0.verifying = false }
                moved()
                refreshPlans()
                return true
            } catch is CancellationError {
                return false
            } catch {
                let transient: Bool
                if let e = error as? AssetStore.DownloadError {
                    switch e {
                    case .paused, .network: transient = true
                    default: transient = false
                    }
                } else {
                    transient = true
                }
                attempt += 1
                if transient && attempt <= 3 {
                    try? await Task.sleep(for: .seconds(5 * attempt))
                    if Task.isCancelled { return false }
                    continue
                }
                let storage: Bool = if case .storage = error as? AssetStore.DownloadError { true } else { false }
                update(a.id) { $0.error = error.localizedDescription; $0.verifying = false; $0.storage = storage }
                return false
            }
        }
    }

    private func moved() {
        let now = Date()
        let bytes = doneBytes
        if bytes != lastMove.bytes { lastMove = (bytes, now) }
        let start = rateStart ?? (bytes, now)
        rateStart = start
        let elapsed = now.timeIntervalSince(start.at)
        let bps = Double(bytes - start.bytes) / max(elapsed, 1)
        etaSeconds = elapsed >= 5 && bps > 0 ? Int(Double(totalBytes - bytes) / bps) : nil
        stalled = false
    }

    /// No byte for a minute while a download runs: offer to restart (the Expo wizard's STALL_MS).
    private func watchStall() {
        stallWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let running = self.job != nil && self.step == .install && !self.allPresent
                let stalled = running && Date().timeIntervalSince(self.lastMove.at) > Self.stallSeconds
                if stalled != self.stalled { self.stalled = stalled }
            }
        }
    }

    /// Back in the app: retry what retrying can fix (stalls, network), as the Expo wizard does on AppState active.
    func onForeground() {
        refreshPlans()
        if step == .install && job == nil && !failed.isEmpty && !failed.contains(where: \.storage) { install() }
    }

    /// "Restart downloads": drops the running transfer and starts again from the bytes on disk.
    func restartDownloads() {
        job?.cancel()
        job = nil
        install()
    }

    func retry() { install() }

    /// Runs the index again after it failed.
    func retryIndex() {
        if job != nil { return }
        job = Task {
            defer { self.job = nil }
            await index()
        }
    }

    /// A smaller package after a storage failure.
    func smallerPackage() {
        job?.cancel()
        job = nil
        choosePackage(.essential)
        downloads = []
        setStep(.knowledge)
    }

    private func update(_ id: String, _ change: (inout AssetProgress) -> Void) {
        guard let i = downloads.firstIndex(where: { $0.asset.id == id }) else { return }
        change(&downloads[i])
    }

    // MARK: index

    private func index() async {
        indexPhase = .building
        indexError = nil
        indexStart = nil
        let services = services
        guard let emb = services.installed(.embedding).first else { return indexFailed(String(localized: "The search model is missing.")) }
        let throttle = Throttle(interval: 0.25)
        let stop = StopFlag()
        let work = Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            let embedder: LlamaSession
            do {
                embedder = try await LlamaSession.load(path: services.fileOf(emb).path(percentEncoded: false), params: EngineParams.embedder)
            } catch {
                return .failure(error)
            }
            do {
                var collections: [SeedCorpus.Collection] = []
                if let url = AppPaths.bundled("corpus", ext: "json"), let text = try? String(contentsOf: url, encoding: .utf8) {
                    collections.append(SeedCorpus.Collection(id: SeedCorpus.builtin, docs: try SeedCorpus.docs(collectionId: SeedCorpus.builtin, json: text)))
                }
                for p in services.catalog.corpusCatalog where p.format != "sqlite-pack" && services.isPresent(p) {
                    do {
                        let text = try String(contentsOf: services.fileOf(p), encoding: .utf8)
                        collections.append(SeedCorpus.Collection(id: p.id, docs: try SeedCorpus.docs(collectionId: p.id, json: text)))
                    } catch {
                        collections.append(SeedCorpus.Collection(id: p.id, docs: [], error: error.localizedDescription))
                    }
                }
                _ = try await SeedCorpus(kb: services.knowledgeBase, embed: { try await embedder.embed($0) }).seed(collections, onProgress: { p in
                    guard throttle.ready(force: p.done >= p.total) else { return }
                    Task { @MainActor in self.indexProgress(p) }
                }, shouldStop: { stop.value })
                services.packs.reload()
                await embedder.close()
                return .success(())
            } catch {
                await embedder.close()
                return .failure(error)
            }
        }
        // Cancelling setup (Restart, Recovery) stops the seeding between documents; the embedder is always closed.
        let result = await withTaskCancellationHandler { await work.value } onCancel: { stop.set(true) }
        switch result {
        case .success: indexPhase = .ready
        case .failure(let e): indexFailed(e.localizedDescription)
        }
    }

    private func indexProgress(_ p: SeedCorpus.Progress) {
        let now = Date()
        let start = indexStart ?? (p.done, now)
        indexStart = start
        let elapsed = now.timeIntervalSince(start.at)
        let indexed = p.done - start.done
        indexEtaSeconds = elapsed >= 3 && indexed >= 5 ? Int(Double(p.total - p.done) * elapsed / Double(indexed)) : nil
        indexDone = p.done
        indexTotal = p.total
        indexTitle = p.title
    }

    private func indexFailed(_ message: String) {
        indexPhase = .error
        indexError = message
    }

    // MARK: persistence (setup_progress.json, same keys as Android)

    private func restore() {
        guard let data = try? Data(contentsOf: AppPaths.setupProgress), let o = JSONValue(jsonString: String(decoding: data, as: UTF8.self)) else { return }
        packageChosen = o["packageChosen"]?.boolValue ?? false
        answerChosen = o["answerChosen"]?.boolValue ?? false
        if let id = o["chosenId"]?.stringValue, !id.isEmpty, let m = services.catalog.byId(id) {
            if !models.contains(where: { $0.id == m.id }) { models.append(m) }
            if answerChosen { chosenId = id }
        }
        step = Step(rawValue: min(max(o["step"]?.intValue ?? 1, 1), 4)) ?? .welcome
        if let p = o["packageId"]?.stringValue.flatMap(SetupPackage.init(rawValue:)) { package = p }
        // A lock turned on from the guide keeps its page: the pages after it don't shift. The guide opens on its first page.
        let resumed = SetupGuide.resume(experimental: LabsBuild.experimental, pinPage: o["pinPage"]?.boolValue, pinSetNow: Self.lockOn(services),
                                        notifications: false, page: nil)
        pages = resumed.pages.filter { $0 != .files }
        guidePage = resumed.index
    }

    private func save() {
        let o: JSONValue = .object([
            "step": JSONValue(step.rawValue), "packageId": .string(package.rawValue), "chosenId": .string(chosenId ?? ""),
            "packageChosen": .bool(packageChosen), "answerChosen": .bool(answerChosen),
            "guidePage": .string(page.rawValue), "pinPage": .bool(pages.contains(.pin)),
        ])
        try? Data(o.jsonString.utf8).write(to: AppPaths.setupProgress, options: .atomic)
    }
}

#if DEBUG
extension SetupFlow {
    /// UI audit (`-uiScreen setup-install / setup-index`): step 4 mid-download or mid-index, without the network.
    func debugShowInstall(indexing: Bool) {
        let assets = assetsOf(package)
        downloads = assets.enumerated().map { i, a in
            if indexing || i == 0 { return AssetProgress(asset: a, bytesDone: a.sizeBytes, done: true) }
            return AssetProgress(asset: a, bytesDone: i == 1 ? Int64(Double(a.sizeBytes) * 0.38) : 0)
        }
        step = .install
        etaSeconds = indexing ? nil : 312
        if indexing {
            indexPhase = .building
            indexDone = 1_840
            indexTotal = 6_200
            indexTitle = "Photosynthesis"
            indexEtaSeconds = 95
        }
    }
}
#endif

/// Lets through at most one call per `interval` (and every forced one), from any thread.
final class Throttle: Sendable {
    private let interval: TimeInterval
    private let last = Mutex<Date>(.distantPast)

    init(interval: TimeInterval) { self.interval = interval }

    func ready(force: Bool = false) -> Bool {
        last.withLock { last in
            let now = Date()
            guard force || now.timeIntervalSince(last) >= interval else { return false }
            last = now
            return true
        }
    }
}
