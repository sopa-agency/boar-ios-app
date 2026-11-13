/// What the chat loads on its own (at start, or for a question while no model is loaded). It never loads a model whose
/// last load closed the app (`LoadGuard.isBlocked`), nor one rated RED for this phone (`Compatibility.compute`) unless the
/// user chose "Load anyway" for it. Nothing is hard-blocked: the chat offers the choice (`Decision`)
/// (android `engine/models/StartLoad.kt`).
public enum StartLoad {
    /// `streamed`: runs on an engine that streams it from storage (Android's Boar Labs Big Boar), so it never has to fit
    /// in RAM. iOS has no such engine: always false here, kept for parity.
    public struct Model: Sendable, Equatable {
        public var id: String
        public var sizeBytes: Int64
        public var streamed: Bool

        public init(id: String, sizeBytes: Int64, streamed: Bool = false) {
            self.id = id; self.sizeBytes = sizeBytes; self.streamed = streamed
        }
    }

    public enum Decision: Sendable, Equatable {
        /// Load `modelId` (GREEN, YELLOW, unknown RAM, or RED the user already chose to load).
        case load(modelId: String)
        /// RED without "Load anyway": nothing loads; the chat asks. `onlyModel`: no other model is installed.
        case askRisky(modelId: String, onlyModel: Bool)
        /// `blockedId` closed the app last time: `modelId` answers instead (the last that loaded, else the smallest).
        case fallback(blockedId: String, modelId: String)
        /// `blockedId` closed the app last time and no other installed model can answer. `onlyModel`: it's the only one.
        case noFallback(blockedId: String, onlyModel: Bool)
        /// No model installed.
        case noModel
    }

    /// `active` is the user's model (nil when none is installed); `installed` every installed LLM; `lastLoadedId` the
    /// last model that loaded; `loadAnyway` the models the user chose to load although RED.
    public static func decide(
        active: Model?, installed: [Model], isBlocked: (String) -> Bool, lastLoadedId: String?, totalRamBytes: Int64,
        loadAnyway: Set<String>
    ) -> Decision {
        guard let active else { return .noModel }
        let onlyModel = !installed.contains { $0.id != active.id }
        if isBlocked(active.id) {
            if let fallback = fallback(installed: installed, isBlocked: isBlocked, lastLoadedId: lastLoadedId) {
                return .fallback(blockedId: active.id, modelId: fallback.id)
            }
            return .noFallback(blockedId: active.id, onlyModel: onlyModel)
        }
        if risky(active, totalRamBytes: totalRamBytes) && !loadAnyway.contains(active.id) {
            return .askRisky(modelId: active.id, onlyModel: onlyModel)
        }
        return .load(modelId: active.id)
    }

    /// The model that answers instead of a blocked one: the last that loaded, else the smallest installed, never a
    /// blocked one.
    public static func fallback(installed: [Model], isBlocked: (String) -> Bool, lastLoadedId: String?) -> Model? {
        let ok = installed.filter { !isBlocked($0.id) }
        if let lastLoadedId, let last = ok.first(where: { $0.id == lastLoadedId }) { return last }
        // Kotlin's minByOrNull: the first of equal sizes.
        return ok.reduce(nil) { best, m in best.map { m.sizeBytes < $0.sizeBytes ? m : $0 } ?? m }
    }

    /// RED for this phone; unknown RAM, or a model an engine streams from storage, is never risky.
    public static func risky(_ model: Model, totalRamBytes: Int64) -> Bool {
        !model.streamed && Compatibility.compute(sizeBytes: model.sizeBytes, deviceRamBytes: totalRamBytes) == .red
    }
}
