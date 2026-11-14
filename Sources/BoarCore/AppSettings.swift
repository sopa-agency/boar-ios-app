import Foundation

/// The app's settings over a `KeyValueStore`, under the same keys the Android and Expo apps use, so a JSON-file store can
/// read their file as is. Keys this build doesn't know stay in the store untouched. Every property reads and writes through
/// the store (no cache), so two `AppSettings` over one store agree.
///
/// Models-owned records (the load-guard ledger, the PIN) are exposed as plain keys/values here: BoarModels builds its
/// `LoadGuard.Ledger` on `loadCrashedIds`, `loadMappedIds` and `pendingLoadCrash`.
public final class AppSettings: @unchecked Sendable {
    public let store: KeyValueStore
    private let writeLock = NSLock()
    private var changeHook: (@Sendable (String, JSONValue?, JSONValue?) -> Void)?

    /// Called after a setting changes, with its key, old and new value (android AppSettings.onChange: the debug log).
    public var onChange: (@Sendable (String, JSONValue?, JSONValue?) -> Void)? {
        get { writeLock.withLock { changeHook } }
        set { writeLock.withLock { changeHook = newValue } }
    }

    public init(store: KeyValueStore) {
        self.store = store
        // Executive Summary became Personal Files (rc1): a saved Summary opens in Detailed, the default, not in a style
        // that answers only from the user's files.
        if str("personalityId") == Self.retiredSummaryStyle { set("personalityId", .string("detailed")) }
    }

    // MARK: typed access

    private func str(_ key: String) -> String? { store.value(forKey: key)?.stringValue }
    private func int(_ key: String) -> Int? { store.value(forKey: key)?.intValue }
    private func bool(_ key: String) -> Bool? { store.value(forKey: key)?.boolValue }
    private func set(_ key: String, _ value: JSONValue?) {
        let (old, hook) = writeLock.withLock { () -> (JSONValue?, (@Sendable (String, JSONValue?, JSONValue?) -> Void)?) in
            let old = store.value(forKey: key)
            store.setValue(value, forKey: key)
            return (old, changeHook)
        }
        let new = value.flatMap { $0.isNull ? nil : $0 }
        if let hook, old != new { hook(key, old, new) }
    }
    private func strings(_ key: String) -> [String] { store.value(forKey: key)?.arrayValue?.compactMap(\.stringValue) ?? [] }
    private func setStrings(_ key: String, _ v: [String]) { set(key, v.isEmpty ? nil : JSONValue(strings: v)) }

    /// The stored JSON node for a key (for records this module doesn't model).
    public func jsonValue(forKey key: String) -> JSONValue? { store.value(forKey: key) }
    public func setJSONValue(_ v: JSONValue?, forKey key: String) { set(key, v) }
    /// Every key as stored, for tests and diagnostics.
    public func raw() -> [String: JSONValue] { store.allValues() }

    // MARK: models

    /// activeModelId.llm, .embedding…
    public func activeModelId(_ kind: String) -> String? {
        store.value(forKey: "activeModelId")?[kind]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func setActiveModelId(_ kind: String, _ id: String?) {
        writeLock.withLock {
            var m = store.value(forKey: "activeModelId")?.objectValue ?? [:]
            if let id { m[kind] = .string(id) } else { m[kind] = nil }
            store.setValue(.object(m), forKey: "activeModelId")
        }
    }

    /// modelRoleAssignments: role ("fast", "general"…) to model id.
    public func modelRoleAssignments() -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in store.value(forKey: "modelRoleAssignments")?.objectValue ?? [:] {
            if let s = v.stringValue, !s.isEmpty { out[k] = s }
        }
        return out
    }

    // MARK: answer style and length

    public var personalityId: String? { get { str("personalityId") } set { set("personalityId", newValue.map(JSONValue.string)) } }
    public var customSystemPrompt: String? { get { str("customSystemPrompt") } set { set("customSystemPrompt", newValue.map(JSONValue.string)) } }
    /// The answer length the user picked in Settings; nil is Auto.
    public var maxTokensChoice: Int? { get { int("maxTokens") } set { set("maxTokens", newValue.map { JSONValue($0) }) } }
    /// The answer's token limit: the user's pick, else Auto by style (and Deep Research).
    public var maxTokens: Int { maxTokensChoice ?? Self.autoMaxTokens(personalityId: personalityId, deepResearch: deepResearchMode) }

    /// The limit for an answer now: the user's pick as is, else Auto fitted to the context the model was opened with.
    public func answerTokens(openedContext: Int?) -> Int {
        maxTokensChoice ?? Self.fitToContext(Self.autoMaxTokens(personalityId: personalityId, deepResearch: deepResearchMode), openedContext: openedContext)
    }

    /// Settings → Reset settings: every preference back to its default. Kept: models and their roles, the PIN, the language,
    /// the custom prompt and the app's own bookkeeping. Chats live elsewhere and stay too.
    public func resetPreferences() { writeLock.withLock { store.removeValues(forKeys: Self.preferenceKeys) } }

    /// What "Reset settings" clears (`resetPreferences`).
    public static let preferenceKeys = [
        "themeId", "fontScale", "personalityId", "maxTokens", "deepResearchMode", "researchBannerHidden",
        "adaptiveRoutingEnabled", "routingPreset", "engineTweaks", "showLiveStats", "voiceInputEnabled", "hapticsEnabled",
        "hidePromptIdeas", "autoSummarize", "historyTurnThreshold", "maxSavedSessions", "autoGenerateTitles",
        "freeMemoryInBackground", "freeMemoryAfterMinutes", "confirmChatDelete",
    ]
    public static let defaultMaxTokens = 512
    /// Detailed answers ran past 512 tokens and stopped mid-sentence.
    public static let detailedMaxTokens = 1024
    /// Personal Files: the fact first, then two to four sentences; between Succinct's and Detailed's lengths.
    public static let personalMaxTokens = 768
    /// The retired Executive Summary style's id, moved to Detailed when settings load.
    public static let retiredSummaryStyle = "summary"
    /// A Deep Research write-up, any style; the largest choice in Settings.
    public static let researchMaxTokens = 2048
    /// Context kept for the prompt (instructions, sources, history) when Auto sizes the answer.
    public static let promptReserve = 1500
    /// Auto never goes below this, however small the context.
    public static let minAutoTokens = 256
    /// PBKDF2 rounds for the PIN key (`PinKeys.ITERATIONS` on Android).
    public static let defaultPinIterations = 210_000

    /// Auto length on a small context. Unknown context (no model loaded yet): `cap`.
    public static func fitToContext(_ cap: Int, openedContext: Int?) -> Int {
        guard let openedContext else { return cap }
        return min(cap, max(minAutoTokens, openedContext - promptReserve))
    }

    /// No style set means Detailed, the app's default. Personal Files comes first: Deep Research steps aside in that style.
    public static func autoMaxTokens(personalityId: String?, deepResearch: Bool = false) -> Int {
        if personalityId == "personal" { return personalMaxTokens }
        if deepResearch { return researchMaxTokens }
        if (personalityId ?? "detailed") == "detailed" { return detailedMaxTokens }
        return defaultMaxTokens
    }

    // MARK: switches and display

    public var deepResearchMode: Bool { get { bool("deepResearchMode") ?? false } set { set("deepResearchMode", .bool(newValue)) } }
    /// The user closed the "Mixture of agents" line under the header (it stays closed).
    public var researchBannerHidden: Bool { get { bool("researchBannerHidden") ?? false } set { set("researchBannerHidden", .bool(newValue)) } }
    public var adaptiveRoutingEnabled: Bool { get { bool("adaptiveRoutingEnabled") ?? false } set { set("adaptiveRoutingEnabled", .bool(newValue)) } }
    public var routingPreset: String? { get { str("routingPreset") } set { set("routingPreset", newValue.map(JSONValue.string)) } }
    /// A palette id as Android stores it ("campfire", "moonlight", "paper", a Boar Avatars theme like "tactical_red"), or
    /// "system" on iOS; see `ThemeChoice`.
    public var themeId: String? { get { str("themeId") } set { set("themeId", newValue.map(JSONValue.string)) } }
    public var fontScale: String { get { str("fontScale") ?? "standard" } set { set("fontScale", .string(newValue)) } }
    public var languageId: String? { get { str("languageId") } set { set("languageId", newValue.map(JSONValue.string)) } }
    public var voiceInputEnabled: Bool { get { bool("voiceInputEnabled") ?? true } set { set("voiceInputEnabled", .bool(newValue)) } }
    public var hapticsEnabled: Bool { get { bool("hapticsEnabled") ?? true } set { set("hapticsEnabled", .bool(newValue)) } }
    /// Settings → "Ask before deleting a chat": on by default; off, one tap deletes it.
    public var confirmChatDelete: Bool { get { bool("confirmChatDelete") ?? true } set { set("confirmChatDelete", .bool(newValue)) } }
    /// The Fastest preset's heat and battery warning was shown and accepted once (android `runPresetWarned`).
    public var runPresetWarned: Bool { get { bool("runPresetWarned") ?? false } set { set("runPresetWarned", .bool(newValue)) } }
    /// Settings → "Free memory when I leave BOAR" (FreeMemory): on by default.
    public var freeMemoryInBackground: Bool { get { bool("freeMemoryInBackground") ?? true } set { set("freeMemoryInBackground", .bool(newValue)) } }
    /// Advanced → "Free memory after", in minutes; nil is Auto (at once).
    public var freeMemoryAfterMinutes: Int? { get { int("freeMemoryAfterMinutes") } set { set("freeMemoryAfterMinutes", newValue.map { JSONValue($0) }) } }
    public var hidePromptIdeas: Bool { get { bool("hidePromptIdeas") ?? false } set { set("hidePromptIdeas", .bool(newValue)) } }
    /// Settings → Engine Tweaks → Debug Log (android `debugLogEnabled`).
    public var debugLogEnabled: Bool { get { bool("debugLogEnabled") ?? false } set { set("debugLogEnabled", .bool(newValue)) } }
    /// Advanced tweaks → Show technical details. On by default: the bounty's judges and early users want the numbers.
    public var showLiveStats: Bool { get { bool("showLiveStats") ?? true } set { set("showLiveStats", .bool(newValue)) } }

    // MARK: chat memory (DEFAULT_MEMORY_SETTINGS when unset)

    public var autoSummarize: Bool { get { bool("autoSummarize") ?? true } set { set("autoSummarize", .bool(newValue)) } }
    public var historyTurnThreshold: Int { get { int("historyTurnThreshold") ?? 6 } set { set("historyTurnThreshold", JSONValue(newValue)) } }
    public var maxSavedSessions: Int { get { int("maxSavedSessions") ?? 10 } set { set("maxSavedSessions", JSONValue(newValue)) } }
    public var autoGenerateTitles: Bool { get { bool("autoGenerateTitles") ?? true } set { set("autoGenerateTitles", .bool(newValue)) } }

    // MARK: engine

    /// Advanced tweaks; all Auto when unset or unreadable. All-Auto tweaks are stored as no key at all.
    public var engineTweaks: EngineTweaks {
        get { EngineTweaks.fromJSON(store.value(forKey: "engineTweaks")?.jsonString) }
        set { set("engineTweaks", newValue.isAuto ? nil : JSONValue(jsonString: newValue.toJSON())) }
    }

    // MARK: load guard bookkeeping (Models builds `LoadGuard.Ledger` on these)

    /// The Expo app's `loadCrashedIds`.
    public var loadCrashedIds: [String] { get { strings("loadCrashedIds") } set { setStrings("loadCrashedIds", newValue) } }
    /// `loadMappedIds`: models kept on the mapped file after a repacked load got the app killed.
    public var loadMappedIds: [String] { get { strings("loadMappedIds") } set { setStrings("loadMappedIds", newValue) } }
    /// `pendingLoadCrash` as stored (a JSON object); BoarModels decodes it.
    public var pendingLoadCrash: JSONValue? {
        get { store.value(forKey: "pendingLoadCrash").flatMap { $0.objectValue == nil ? nil : $0 } }
        set { set("pendingLoadCrash", newValue) }
    }

    /// The last model that loaded: the fallback after a crash on a cold start.
    public var lastLoadedModelId: String? { get { str("lastLoadedModelId") } set { set("lastLoadedModelId", newValue.map(JSONValue.string)) } }
    /// The id submit-results gave this device's key.
    public var shareDeviceId: String? { get { str("shareDeviceId") } set { set("shareDeviceId", newValue.map(JSONValue.string)) } }

    // MARK: Boar Avatars

    /// Boar Avatars' `Vault.State` as JSON text, stored as a JSON object like Android's `truffleVault`; nil before
    /// anything was counted, or when the stored value isn't an object.
    public var truffleVault: String? {
        get { store.value(forKey: "truffleVault").flatMap { $0.objectValue == nil ? nil : $0.jsonString } }
        set { set("truffleVault", newValue.flatMap { JSONValue(jsonString: $0) }) }
    }
    /// The equipped avatar's id (android `iconId`); nil for BOAR's own.
    public var iconId: String? { get { str("iconId") } set { set("iconId", newValue.map(JSONValue.string)) } }

    // MARK: PIN lock (the Keychain/LocalAuthentication path replaces this on iOS; kept for parity and migration)

    public var pinWrapped: String? { get { str("pinWrapped") } set { set("pinWrapped", newValue.map(JSONValue.string)) } }
    public var pinSalt: String? { get { str("pinSalt") } set { set("pinSalt", newValue.map(JSONValue.string)) } }
    public var pinIterations: Int { get { int("pinIterations") ?? Self.defaultPinIterations } set { set("pinIterations", JSONValue(newValue)) } }
    public var pinFailures: Int { get { int("pinFailures") ?? 0 } set { set("pinFailures", JSONValue(newValue)) } }
    public var pinLockedUntil: Int64 { get { store.value(forKey: "pinLockedUntil")?.int64Value ?? 0 } set { set("pinLockedUntil", .int(newValue)) } }
}
