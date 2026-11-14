import BoarAnswer
import BoarCore
import BoarLlama
import BoarModels
import BoarRAG
import BoarRemote
import Foundation
import os

/// Everything the screens share, opened once per process (port of android `BoarServices.kt`): settings, the catalog
/// (built-in plus models added from Hugging Face), the knowledge base and chats on one SQLite connection, the installed
/// knowledge packs, the embedder, the retriever and the generation model host.
///
/// Thread-safe: immutable references plus lock-protected caches. Blocking SQLite work must run off the main actor
/// (`AppModel` creates this on a background task; `ChatController` goes through `background { }`).
final class BoarServices: @unchecked Sendable {
    static let defaultPersonalityId = "detailed"
    private static let log = BoarLog.logger("app")

    let filesDir: URL
    let settings: AppSettings
    let personalities: Personalities
    let suggestions: Suggestions
    let topology: CpuTopology
    let totalRamBytes: Int64
    let knowledgeBase: KnowledgeBase
    let chats: ChatStore
    let loadGuard: LoadGuard
    let packs: PackRegistry
    let embedder: EmbedderHost
    let lexicon: LexiconStore
    let retriever: Retriever
    let host: SessionHost
    let assets: AssetStore
    let downloads: BackgroundDownloads
    /// Boar Avatars: what using the app unlocks, counted on the device.
    let vault: TruffleVault

    private let baseCatalog: Catalog
    private let catalogLock = OSAllocatedUnfairLock<Catalog?>(initialState: nil)
    private let kbDb: SqliteDatabase

    init(filesDir: URL = AppPaths.filesDir) throws {
        self.filesDir = filesDir
        let settings = AppSettings(store: UserDefaultsKeyValueStore(defaults: AppPaths.defaults))
        self.settings = settings
        baseCatalog = try Catalog.bundled()
        var personalities = try Personalities.bundled()
        // The native app starts on Detailed (the Expo app on Succinct); a style the user picked is kept.
        personalities.defaultId = Self.defaultPersonalityId
        self.personalities = personalities
        suggestions = try Suggestions.bundled()
        topology = CpuTopology.read()
        totalRamBytes = DebugLaunch.ramBytes ?? DeviceMemory.totalBytes

        kbDb = try SqliteDatabase(path: AppPaths.knowledgeBase.path(percentEncoded: false))
        knowledgeBase = try KnowledgeBase(db: kbDb)
        chats = try ChatStore(db: kbDb)
        loadGuard = LoadGuard(store: FileMarkerStore(url: AppPaths.loadMarker), ledger: SettingsLoadLedger(settings: settings))

        let catalog = Self.withDiscovered(baseCatalog)
        catalogLock.withLock { $0 = catalog }
        let embeddingSha = catalog.models.first { $0.kind == .embedding && $0.required }?.sha256 ?? ""
        packs = PackRegistry(filesDir: filesDir, embeddingSha: embeddingSha)
        embedder = EmbedderHost(filesDir: filesDir)
        lexicon = LexiconStore()
        let packs = packs, embedder = embedder, lexicon = lexicon
        let catalogBox = catalogLock
        retriever = Retriever(
            kb: knowledgeBase,
            packs: { packs.open(catalog: catalogBox.withLock { $0 } ?? catalog) },
            embed: { text in try await embedder.embed(text, catalog: catalogBox.withLock { $0 } ?? catalog) },
            lexicon: { lexicon.lexicon }
        )
        host = SessionHost(settings: settings, loadGuard: loadGuard, topology: topology, totalRamBytes: totalRamBytes, filesDir: filesDir) {
            catalogBox.withLock { $0 } ?? catalog
        }
        assets = AssetStore(filesDir: filesDir, catalog: catalog, log: { Self.log.info("\($0, privacy: .public)") })
        downloads = BackgroundDownloads.shared
        vault = TruffleVault(settings: settings)
    }

    // MARK: catalog

    /// The built-in catalog plus the models added from Hugging Face (listed after it, never twice).
    var catalog: Catalog { catalogLock.withLock { $0 } ?? baseCatalog }

    /// A source under an answer, read whole from the phone (SourceArticle): the pack article or the user's file. Nil
    /// when its pack or collection is gone. Database work: call it off the main actor.
    func readSource(docId: String, title: String) -> SourceArticle.Article? {
        SourceArticle.read(docId: docId, title: title, kb: knowledgeBase, packs: packs.open(catalog: catalog))
    }

    /// Models added from the Hugging Face search (discoveredModels.ts, same file as the Expo app).
    func discovered() -> [CatalogAsset] {
        Self.readDiscovered()
    }

    func addDiscovered(_ asset: CatalogAsset) {
        catalogLock.withLock { current in
            var all = Self.readDiscovered()
            // Stamped only when new (android BoarServices.addDiscovered): adding it again keeps its place in Recently Added.
            if !all.contains(where: { $0.id == asset.id }) {
                all.append(asset)
                settings.stampModel(AppSettings.modelAdded, asset.id)
            }
            Self.writeDiscovered(all)
            current = Self.withDiscovered(baseCatalog)
        }
    }

    func removeDiscovered(_ id: String) {
        catalogLock.withLock { current in
            Self.writeDiscovered(Self.readDiscovered().filter { $0.id != id })
            current = Self.withDiscovered(baseCatalog)
        }
    }

    private static func readDiscovered() -> [CatalogAsset] {
        guard let data = try? Data(contentsOf: AppPaths.discoveredModels) else { return [] }
        return (try? JSONDecoder().decode([CatalogAsset].self, from: data)) ?? []
    }

    /// Written atomically: a failed write never leaves a truncated list.
    private static func writeDiscovered(_ list: [CatalogAsset]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: AppPaths.discoveredModels, options: .atomic)
    }

    private static func withDiscovered(_ base: Catalog) -> Catalog {
        var c = base
        let extra = readDiscovered().filter { d in !base.models.contains { $0.filename == d.filename } }
        c.models += extra
        return c
    }

    // MARK: Boar Avatars

    /// What the vault reads from the app's files (android `BoarServices.checkVault`): installed knowledge packs (the
    /// catalog's and other `.sqlite` files in corpus/) and models added from Hugging Face. File checks: call it off the
    /// main actor.
    func vaultReadings() -> (packs: Int, hfModels: Int) {
        let fm = FileManager.default
        let catalogFiles = catalog.corpusCatalog.map { filesDir.appending(path: $0.filename).standardizedFileURL }
        let installed = catalog.corpusCatalog.filter {
            $0.format == "sqlite-pack" && fm.fileExists(atPath: filesDir.appending(path: $0.filename).path(percentEncoded: false))
        }.count
        let corpus = (try? fm.contentsOfDirectory(at: filesDir.appending(path: "corpus"), includingPropertiesForKeys: nil)) ?? []
        let local = corpus.filter { $0.pathExtension == "sqlite" && !catalogFiles.contains($0.standardizedFileURL) }.count
        return (installed + local, discovered().count)
    }

    // MARK: installed models

    func fileOf(_ asset: CatalogAsset) -> URL { filesDir.appending(path: asset.filename) }

    func isPresent(_ asset: CatalogAsset) -> Bool {
        FileManager.default.fileExists(atPath: fileOf(asset).path(percentEncoded: false))
    }

    func installed(_ kind: AssetKind) -> [CatalogAsset] { catalog.models.filter { $0.kind == kind && isPresent($0) } }

    /// The user's model, else the first installed one (the catalog's order puts the default first).
    func activeModel() -> CatalogAsset? {
        if let id = settings.activeModelId("llm"), let m = catalog.byId(id), isPresent(m) { return m }
        return installed(.llm).first
    }

    /// The model the chat answers with: the active one, unless its load killed the app (CR-2). Then the model loaded
    /// before it, else the smallest installed one that isn't blocked.
    func answerModel() -> CatalogAsset? {
        guard let m = activeModel() else { return nil }
        if !loadGuard.isBlocked(m.id) { return m }
        let ok = installed(.llm).filter { !loadGuard.isBlocked($0.id) }
        if let last = settings.lastLoadedModelId, let found = ok.first(where: { $0.id == last }) { return found }
        return ok.min { $0.sizeBytes < $1.sizeBytes }
    }

    /// Everything BOAR keeps on the phone: models, packs, the knowledge base with imported documents, chats, settings.
    func storageUsedBytes() -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: filesDir, includingPropertiesForKeys: Array(keys)) else { return 0 }
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            // Allocated size first: a sparse or compressed file takes less than its length (what iOS Settings counts).
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }

    // MARK: model backend (iOS only)

    /// Which engine answers: llama.cpp with a downloaded GGUF (default), or Apple's on-device model when the phone has it.
    var backend: ModelBackend {
        get { settings.jsonValue(forKey: ModelBackend.settingsKey)?.stringValue.flatMap(ModelBackend.init(rawValue:)) ?? .llama }
        set { settings.setJSONValue(newValue == .llama ? nil : .string(newValue.rawValue), forKey: ModelBackend.settingsKey) }
    }

    /// The session the default path answers with: Apple's model when chosen and available, the Mac on the network when
    /// chosen (nil while it can't be reached, so the answer says why), else the active GGUF loaded through the host; nil
    /// when no model is installed or it fails to load.
    func activeSession() async -> (any TextModelSession)? {
        if backend == .apple, let apple = await host.loadApple() { return apple }
        if backend == .remote {
            guard let server = RemoteConfig.server(settings) else { return nil }
            return await host.loadRemote(server)
        }
        guard let m = answerModel() else { return nil }
        return await host.loadSession(m.id)
    }

    /// Runs blocking work (SQLite, file scans) off the main actor.
    func background<T: Sendable>(_ body: @escaping @Sendable (BoarServices) throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try body(self) }.value
    }
}

/// The engine that answers. Stored in settings under `iosModelBackend` (not a Kotlin key).
enum ModelBackend: String, Sendable, CaseIterable, Identifiable {
    case llama
    case apple
    /// llama-server on another computer in the same network (a Mac mini); search and chats stay on this device.
    case remote
    static let settingsKey = "iosModelBackend"
    var id: String { rawValue }
}

/// The installed knowledge packs, opened on first search (catalog packs first, then other `.sqlite` files by name).
final class PackRegistry: @unchecked Sendable {
    private let filesDir: URL
    private let embeddingSha: String
    private let lock = OSAllocatedUnfairLock<[OpenPack]?>(initialState: nil)
    private static let log = BoarLog.logger("packs")

    init(filesDir: URL, embeddingSha: String) {
        self.filesDir = filesDir
        self.embeddingSha = embeddingSha
    }

    func open(catalog: Catalog) -> [OpenPack] {
        if let p = lock.withLock({ $0 }) { return p }
        let scanned = scan(catalog)
        return lock.withLock { current in
            if let existing = current {
                for p in scanned { Self.close(p) }
                return existing
            }
            current = scanned
            return scanned
        }
    }

    /// After a pack is downloaded or removed: the next search opens the current set.
    func reload() {
        let old = lock.withLock { current -> [OpenPack] in
            defer { current = nil }
            return current ?? []
        }
        for p in old { Self.close(p) }
    }

    private static func close(_ p: OpenPack) {
        switch p {
        case .format1(_, let db): db.close()
        case .format2(_, let pack): pack.close()
        }
    }

    private func scan(_ catalog: Catalog) -> [OpenPack] {
        let fm = FileManager.default
        let catalogFiles = catalog.corpusCatalog.filter { $0.format == "sqlite-pack" }.map { ($0.id, filesDir.appending(path: $0.filename)) }
        let corpusDir = filesDir.appending(path: "corpus")
        let local = ((try? fm.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter { f in !catalogFiles.contains { $0.1.standardizedFileURL == f.standardizedFileURL } }
            .map { ("local-\($0.deletingPathExtension().lastPathComponent)", $0) }
        return (catalogFiles + local).compactMap { id, url -> OpenPack? in
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            do {
                // Writable: a format-2 pack keeps its query vocabulary in temp tables on this connection.
                let db = try SqliteDatabase(path: url.path(percentEncoded: false))
                let meta = Dictionary(try db.query("SELECT key, value FROM meta") { ($0.string(0) ?? "", $0.string(1) ?? "") }, uniquingKeysWith: { $1 })
                switch Packs.packFormat(meta, embeddingSha256: embeddingSha) {
                case 1: return .format1(id, db)
                case 2: return .format2(id, try WikiPack.open(db: db, zstd: ZstdDecoder()))
                default:
                    db.close()
                    return nil
                }
            } catch {
                Self.log.error("pack \(id, privacy: .public) not opened: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}

/// The embedding model, loaded on first use; an empty vector when none is installed (keyword search only).
actor EmbedderHost {
    private let filesDir: URL
    private var session: LlamaSession?

    init(filesDir: URL) { self.filesDir = filesDir }

    func embed(_ text: String, catalog: Catalog) async throws -> [Float] {
        if session == nil {
            guard let asset = catalog.models.first(where: { $0.kind == .embedding && FileManager.default.fileExists(atPath: filesDir.appending(path: $0.filename).path(percentEncoded: false)) })
            else { return [] }
            let mark = BoarPerf.begin("embedder.load", asset.id)
            defer { mark.end() }
            session = try await LlamaSession.load(path: filesDir.appending(path: asset.filename).path(percentEncoded: false), params: EngineParams.embedder)
        }
        return try await session?.embed(text) ?? []
    }

    func unload() async {
        await session?.close()
        session = nil
    }
}

/// Portuguese article names for PT questions (pt-en.json in the app bundle), parsed on first use.
final class LexiconStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<PtLexicon.Lexicon?>(initialState: nil)

    var lexicon: PtLexicon.Lexicon {
        if let l = lock.withLock({ $0 }) { return l }
        let parsed: PtLexicon.Lexicon
        if let url = AppPaths.bundled("pt-en", ext: "json"), let data = try? Data(contentsOf: url), let l = try? PtLexicon.Lexicon(jsonData: data) {
            parsed = l
        } else {
            parsed = PtLexicon.Lexicon([:])
        }
        return lock.withLock { current in
            if let c = current { return c }
            current = parsed
            return parsed
        }
    }
}
