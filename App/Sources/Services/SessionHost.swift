import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarLlama
import BoarModels
import BoarRemote
import Foundation
import os

/// One generation model at a time, loaded with the user's Advanced tweaks (android `BoarServices.SessionHost`).
///
/// Loads are serialized (Kotlin's Mutex): a second `load` waits for the first. The resident session is mirrored in a
/// lock so `cancel()` (the Stop button) reaches it at once from any thread. Apple's on-device model is an alternative
/// resident session; loading one frees the other.
actor SessionHost: ModelHost {
    private let settings: AppSettings
    private let loadGuard: LoadGuard
    private let topology: CpuTopology
    private let totalRamBytes: Int64
    private let filesDir: URL
    private let catalog: @Sendable () -> Catalog
    private static let log = BoarLog.logger("host")

    private let resident = OSAllocatedUnfairLock<(any TextModelSession)?>(initialState: nil)
    private let context = OSAllocatedUnfairLock<Int?>(initialState: nil)
    private let loadTime = OSAllocatedUnfairLock<Double?>(initialState: nil)
    /// Models that stalled with repacked weights in this process: mapped from storage until the app restarts (#73).
    private let keepMapped = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    /// The GGUF loaded last whose load guard marker is still open (LoadGuard.settled), and that load's number: a timer
    /// from an earlier load of the same model doesn't settle a newer one.
    private let unsettled = OSAllocatedUnfairLock<(id: String, load: Int)?>(initialState: nil)
    private var loadCount = 0
    /// A model loaded this long without the app being killed fits (android LOAD_SETTLE_MS).
    static let loadSettleSeconds = 60

    private var llama: LlamaSession?
    private var apple: (any TextModelSession)?
    private var remote: RemoteSession?
    /// Why the last connection to the Mac on the network failed, for the chat's error row.
    private let remoteError = OSAllocatedUnfairLock<String?>(initialState: nil)
    private var filename: String?
    private var residentId: String?
    private var residentRepacked = false
    private var tail: Task<Void, Never>?

    init(settings: AppSettings, loadGuard: LoadGuard, topology: CpuTopology, totalRamBytes: Int64, filesDir: URL, catalog: @escaping @Sendable () -> Catalog) {
        self.settings = settings
        self.loadGuard = loadGuard
        self.topology = topology
        self.totalRamBytes = totalRamBytes
        self.filesDir = filesDir
        self.catalog = catalog
    }

    // MARK: lock-free reads

    /// The loaded session (llama or Apple), for the default path.
    nonisolated var current: (any TextModelSession)? { resident.withLock { $0 } }
    /// The context window the resident model was opened with (sizes Auto answer length); nil before a load.
    nonisolated var openedContext: Int? { context.withLock { $0 } }
    /// How long the last load took, in ms (nil when the model was already resident for the latest request).
    nonisolated var lastLoadMs: Double? { loadTime.withLock { $0 } }
    /// Stops the generation in flight (the stream still ends with `.done`, stopReason "cancelled").
    nonisolated func cancel() { current?.cancel() }

    /// The resident model's load is known not to have killed the app (LoadGuard.settled): its first answer finished, a
    /// minute passed, it's being closed, or BOAR left the screen (a kill from then on is iOS reclaiming a background app).
    nonisolated func settleResident() { settle(load: nil) }

    /// ⌘Q on the Mac: settles the resident model and also drops the marker of a load still in flight, which
    /// `settleResident` can't reach (it isn't resident yet), or the next launch would block that model.
    nonisolated func appWillQuit() {
        settle(load: nil)
        loadGuard.quitting()
    }

    /// `load`: only that load (a timer's), nil for whatever is resident.
    private nonisolated func settle(load: Int?) {
        let open = unsettled.withLock { u -> String? in
            guard let current = u, load == nil || current.load == load else { return nil }
            u = nil
            return current.id
        }
        if let open { loadGuard.settled(open) }
    }

    // MARK: ModelHost

    func residentFilename() async -> String? { filename }

    func filenameOf(_ modelId: String) async -> String? {
        guard let a = catalog().byId(modelId), exists(a) else { return nil }
        return a.filename
    }

    func load(_ modelId: String) async throws -> (any StepEngine)? {
        guard let s = await loadSession(modelId) else { return nil }
        return SessionEngine(s, enableThinking: settings.engineTweaks.thinkingEnabled)
    }

    // MARK: loading

    /// Loads `modelId` unless it is resident; nil when it isn't installed or fails to load.
    func loadSession(_ modelId: String) async -> (any TextModelSession)? {
        let previous = tail
        let work = Task { () -> (any TextModelSession)? in
            await previous?.value
            return await self.doLoad(modelId)
        }
        tail = Task { _ = await work.value }
        return await work.value
    }

    private func doLoad(_ modelId: String) async -> (any TextModelSession)? {
        let cat = catalog()
        guard let asset = cat.byId(modelId), exists(asset) else { return nil }
        let tweaks = settings.engineTweaks
        let mapped = keepMapped.withLock { $0.contains(asset.id) }
        // A stall while repacked: reload as the mapped file before the next generation.
        let reloadMapped = filename == asset.filename && residentRepacked && mapped && tweaks.weightRepack != true
        if filename == asset.filename, llama != nil, !reloadMapped {
            loadTime.withLock { $0 = nil }
            return current
        }
        // The model answers fall back to if this load kills the app; never the model being loaded itself.
        let previousMeta = (residentId ?? settings.lastLoadedModelId).flatMap(cat.byId).flatMap { $0.id != asset.id ? $0 : nil }
            .map { LoadGuard.Meta(filename: $0.filename, modelId: $0.id, label: $0.label) }
        await closeAll()

        let meta = LoadGuard.Meta(filename: asset.filename, modelId: asset.id, label: asset.label)
        let repack = tweaks.weightRepack ?? !(loadGuard.mappedNext(asset.id) || mapped)
        loadGuard.begin(meta, previous: previousMeta, repacked: repack)
        var params = tweaks.resolve(topology, totalRamBytes: totalRamBytes).params
        params.repack = repack
        let start = ContinuousClock.now
        let mark = BoarPerf.begin("model.load", "\(asset.id) \(LlamaSession.metalEnabled ? "metal" : "cpu") repack=\(repack) threads=\(params.threads)")
        let loaded: LlamaSession
        do {
            loaded = try await LlamaSession.load(path: filesDir.appending(path: asset.filename).path(percentEncoded: false), params: params)
            mark.end("ok")
        } catch {
            mark.end("failed")
            loadGuard.end(meta, loaded: false)
            Self.log.error("\(asset.id, privacy: .public) failed to load: \(String(describing: error), privacy: .public)")
            return nil
        }
        loadGuard.end(meta, loaded: true)
        // The marker stays until the model proves it fits: its first answer, a minute loaded, or leaving the screen.
        loadCount += 1
        let thisLoad = loadCount
        unsettled.withLock { $0 = (asset.id, thisLoad) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.loadSettleSeconds))
            self?.settle(load: thisLoad)
        }
        let elapsed = start.duration(to: .now)
        loadTime.withLock { $0 = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15 }

        llama = loaded
        filename = asset.filename
        residentId = asset.id
        residentRepacked = repack
        let nCtx = params.nCtx
        context.withLock { $0 = nCtx }
        settings.lastLoadedModelId = asset.id
        settings.stampModel(AppSettings.modelLastUsed, asset.id)
        let id = asset.id
        let keep = keepMapped
        // A finished answer proves the model fits: the load guard's marker can go.
        let session: any TextModelSession = MetricsObservingSession(loaded) { [weak self] m in
            self?.settle(load: thisLoad)
            if repack, LoadGuard.isDecodeStall(generatedTokens: m.generatedTokens, decodeMs: m.decodeMs) {
                let added = keep.withLock { $0.insert(id).inserted }
                if added { Self.log.warning("\(id, privacy: .public) stalled with repacked weights: mapped from the next answer") }
            }
        }
        resident.withLock { $0 = session }
        return session
    }

    /// Apple's on-device model when the phone has it (Apple Intelligence on and the model downloaded); frees a GGUF.
    func loadApple() async -> (any TextModelSession)? {
        if let apple { return apple }
        guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
        let model = AppleSystemModel()
        guard model.availability.isAvailable else { return nil }
        await closeAll()
        apple = model
        context.withLock { $0 = model.contextSize }
        loadTime.withLock { $0 = nil }
        resident.withLock { $0 = model }
        return model
    }

    /// The model served by llama-server on another computer in the network; frees a local model. nil when it can't be
    /// reached (`lastRemoteError` says why).
    func loadRemote(_ server: RemoteServer) async -> (any TextModelSession)? {
        if let remote, remote.server == server { return remote }
        await closeAll()
        do {
            let session = try await RemoteSession.connect(server)
            remote = session
            remoteError.withLock { $0 = nil }
            context.withLock { $0 = session.capabilities.contextTokens }
            loadTime.withLock { $0 = nil }
            resident.withLock { $0 = session }
            return session
        } catch {
            let message = (error as? RemoteServerError)?.description ?? String(describing: error)
            remoteError.withLock { $0 = message }
            Self.log.error("remote server \(server.displayName, privacy: .public) unreachable: \(message, privacy: .public)")
            return nil
        }
    }

    /// The last failed connection to the Mac on the network, in plain words.
    nonisolated var lastRemoteError: String? { remoteError.withLock { $0 } }

    /// Frees the model; the next answer loads it again (with changed Advanced tweaks, or another model).
    func unload() async {
        let previous = tail
        let work = Task { await previous?.value; await self.closeAll() }
        tail = work
        await work.value
    }

    private func closeAll() async {
        // Switching or freeing models: the one going out didn't kill the app.
        settleResident()
        resident.withLock { $0 = nil }
        context.withLock { $0 = nil }
        if let llama { await llama.close() }
        if let apple { await apple.close() }
        if let remote { await remote.close() }
        llama = nil
        apple = nil
        remote = nil
        filename = nil
        residentId = nil
    }

    private func exists(_ asset: CatalogAsset) -> Bool {
        FileManager.default.fileExists(atPath: filesDir.appending(path: asset.filename).path(percentEncoded: false))
    }
}
