import Foundation
import Testing
@testable import BoarCore

@Suite struct AppSettingsTests {
    /// A settings.json as the Expo app writes it, with keys this build doesn't use.
    static let expo = #"""
    {"activeModelId":{"llm":"qwen3-4b-instruct-2507-q4km","embedding":"bge-small-en-v1.5-q8"},"personalityId":"detailed","maxTokens":1024,
    "themeId":"moonlight","fontScale":"large","deepResearchMode":true,"placeTileNames":{"a":"b"},"installId":"abc-123","largeModelConfirmedIds":["x"]}
    """#

    /// A throwaway settings.json path; `text` is written first when given.
    func file(_ text: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("settings.json")
        if let text { try text.write(to: f, atomically: true, encoding: .utf8) }
        return f
    }

    @Test func readsTheExpoAppsSettings() throws {
        let s = AppSettings(store: JSONFileKeyValueStore(url: try file(Self.expo)))
        #expect(s.activeModelId("llm") == "qwen3-4b-instruct-2507-q4km")
        #expect(s.personalityId == "detailed")
        #expect(s.maxTokens == 1024)
        #expect(s.themeId == "moonlight")
        #expect(s.fontScale == "large")
        #expect(s.deepResearchMode)
        #expect(!s.adaptiveRoutingEnabled)
        #expect(s.engineTweaks == EngineTweaks())
    }

    @Test func keepsKeysItDoesntKnowWhenItWrites() throws {
        let f = try file(Self.expo)
        let s = AppSettings(store: JSONFileKeyValueStore(url: f))
        s.maxTokensChoice = 2048
        s.engineTweaks = EngineTweaks(threads: 6, kvCache: .q8_0, stageTimeoutSeconds: 0)
        s.setActiveModelId("llm", "qwen2.5-1.5b-instruct-q4km")
        let again = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(again.maxTokens == 2048)
        #expect(again.engineTweaks == EngineTweaks(threads: 6, kvCache: .q8_0, stageTimeoutSeconds: 0))
        #expect(again.activeModelId("llm") == "qwen2.5-1.5b-instruct-q4km")
        #expect(again.activeModelId("embedding") == "bge-small-en-v1.5-q8")
        #expect(again.raw()["installId"] == "abc-123")
        #expect(again.raw()["placeTileNames"] != nil && again.raw()["largeModelConfirmedIds"] != nil)
        s.engineTweaks = EngineTweaks()
        #expect(AppSettings(store: JSONFileKeyValueStore(url: f)).raw()["engineTweaks"] == nil)
    }

    @Test func modelTimesAndTheModelsScreensOrderSurviveAReopen() throws {
        let f = try file(nil)
        let s = AppSettings(store: JSONFileKeyValueStore(url: f))
        s.stampModel(AppSettings.modelLastUsed, "a", at: 100)
        s.stampModel(AppSettings.modelLastUsed, "b", at: 200)
        s.stampModel(AppSettings.modelLastUsed, "a", at: 300)
        s.stampModel(AppSettings.modelAdded, "c", at: 1_762_819_200_000)
        s.modelSort = "LAST_USED"
        s.modelFilter = "MINE"
        let again = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(again.modelTimes(AppSettings.modelLastUsed) == ["a": 300, "b": 200])
        #expect(again.modelTimes(AppSettings.modelAdded) == ["c": 1_762_819_200_000])
        #expect(again.modelSort == "LAST_USED" && again.modelFilter == "MINE")
    }

    @Test func resetSettingsClearsPreferencesAndKeepsModelsThePinTheLanguageAndTheCustomPrompt() throws {
        let f = try file(nil)
        let s = AppSettings(store: JSONFileKeyValueStore(url: f))
        s.setActiveModelId("llm", "qwen3-4b")
        s.pinSalt = "salt"; s.pinWrapped = "wrapped"
        s.languageId = "pt"; s.customSystemPrompt = "Be brief."
        s.themeId = "campfire"; s.personalityId = "succinct"; s.deepResearchMode = true; s.maxTokensChoice = 2048
        s.fontScale = "large"; s.showLiveStats = false; s.researchBannerHidden = true
        s.engineTweaks = EngineTweaks(threads: 2)
        s.resetPreferences()
        let again = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(again.activeModelId("llm") == "qwen3-4b")
        #expect(again.pinSalt == "salt"); #expect(again.pinWrapped == "wrapped")
        #expect(again.languageId == "pt"); #expect(again.customSystemPrompt == "Be brief.")
        #expect(again.themeId == nil); #expect(again.personalityId == nil); #expect(again.maxTokensChoice == nil)
        #expect(!again.deepResearchMode); #expect(again.showLiveStats); #expect(!again.researchBannerHidden)
        #expect(again.fontScale == "standard")
        #expect(again.engineTweaks == EngineTweaks())
    }

    @Test func missingOrBrokenFileMeansDefaults() throws {
        let stores: [KeyValueStore] = [
            JSONFileKeyValueStore(url: try file(nil)), JSONFileKeyValueStore(url: try file("{not json")),
            JSONFileKeyValueStore(url: try file("[1,2]")), InMemoryKeyValueStore(),
        ]
        for store in stores {
            let s = AppSettings(store: store)
            #expect(s.activeModelId("llm") == nil)
            #expect(s.maxTokens == AppSettings.detailedMaxTokens)
            #expect(s.fontScale == "standard")
            #expect(s.autoSummarize)
        }
    }

    @Test func personalFilesAutoLengthIs768EvenUnderDeepResearch() {
        let s = AppSettings(store: InMemoryKeyValueStore())
        s.personalityId = "personal"
        #expect(s.maxTokens == AppSettings.personalMaxTokens)
        s.deepResearchMode = true
        #expect(s.maxTokens == 768)
    }

    @Test func aSavedExecutiveSummaryOpensInDetailed() {
        let store = InMemoryKeyValueStore()
        store.setValue(.string("summary"), forKey: "personalityId")
        #expect(AppSettings(store: store).personalityId == "detailed")
        store.setValue(.string("succinct"), forKey: "personalityId")
        #expect(AppSettings(store: store).personalityId == "succinct")
    }

    @Test func autoAnswerLengthIs2048WithDeepResearchOnInAnyStyleAndAPickStillWins() {
        let s = AppSettings(store: InMemoryKeyValueStore())
        s.deepResearchMode = true
        #expect(s.maxTokens == AppSettings.researchMaxTokens)
        s.personalityId = "succinct"
        #expect(s.maxTokens == 2048)
        s.maxTokensChoice = 512
        #expect(s.maxTokens == 512)
        s.maxTokensChoice = nil
        s.deepResearchMode = false
        #expect(s.maxTokens == 512)
    }

    @Test func autoLengthFitsTheContextTheModelWasOpenedWithAPickIsKeptAsIs() {
        #expect(AppSettings.fitToContext(2048, openedContext: nil) == 2048)
        #expect(AppSettings.fitToContext(2048, openedContext: 4096) == 2048)
        #expect(AppSettings.fitToContext(2048, openedContext: 3072) == 1572)
        #expect(AppSettings.fitToContext(2048, openedContext: 2048) == 548)
        #expect(AppSettings.fitToContext(1024, openedContext: 1024) == 256)
        let s = AppSettings(store: InMemoryKeyValueStore())
        s.deepResearchMode = true
        #expect(s.answerTokens(openedContext: 2048) == 548)
        #expect(s.answerTokens(openedContext: 4096) == 2048)
        s.maxTokensChoice = 2048
        #expect(s.answerTokens(openedContext: 2048) == 2048)
    }

    @Test func autoAnswerLengthIs1024ForDetailed512ForTheOtherStylesAPickWins() {
        let s = AppSettings(store: InMemoryKeyValueStore())
        #expect(s.maxTokensChoice == nil)
        #expect(s.maxTokens == 1024)
        s.personalityId = "succinct"
        #expect(s.maxTokens == 512)
        s.maxTokensChoice = 2048
        #expect(s.maxTokens == 2048)
        s.maxTokensChoice = nil
        #expect(s.maxTokens == 512)
    }

    // MARK: beyond the Kotlin tests: the store implementations and the Models-facing records

    @Test func userDefaultsStoreKeepsTypesAndIsolatesItsPrefix() throws {
        let suite = "boar-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unrelated", forKey: "other.key")
        let s = AppSettings(store: UserDefaultsKeyValueStore(defaults: defaults))
        s.maxTokensChoice = 1536
        s.hapticsEnabled = false
        s.themeId = "campfire"
        s.engineTweaks = EngineTweaks(kvCache: .q4_0, thinking: true)
        s.pinLockedUntil = 1_760_000_000_000
        let again = AppSettings(store: UserDefaultsKeyValueStore(defaults: defaults))
        #expect(again.maxTokensChoice == 1536)
        #expect(again.hapticsEnabled == false)
        #expect(again.themeId == "campfire")
        #expect(again.engineTweaks == EngineTweaks(kvCache: .q4_0, thinking: true))
        #expect(again.pinLockedUntil == 1_760_000_000_000)
        #expect(Set(again.raw().keys) == ["maxTokens", "hapticsEnabled", "themeId", "engineTweaks", "pinLockedUntil"])
        s.themeId = nil
        #expect(again.themeId == nil)
    }

    @Test func loadLedgerRecordsRoundTrip() {
        let s = AppSettings(store: InMemoryKeyValueStore())
        #expect(s.loadCrashedIds.isEmpty && s.loadMappedIds.isEmpty && s.pendingLoadCrash == nil)
        s.loadCrashedIds = ["a", "b"]
        s.loadMappedIds = ["c"]
        s.pendingLoadCrash = ["modelId": "a", "filename": "a.gguf"]
        #expect(s.loadCrashedIds == ["a", "b"] && s.loadMappedIds == ["c"])
        #expect(s.pendingLoadCrash?["modelId"]?.stringValue == "a")
        s.loadCrashedIds = []
        s.pendingLoadCrash = nil
        #expect(s.raw()["loadCrashedIds"] == nil && s.raw()["pendingLoadCrash"] == nil)
    }

    @Test func modelRoleAssignmentsAndPinDefaults() {
        let s = AppSettings(store: InMemoryKeyValueStore(["modelRoleAssignments": ["fast": "a", "general": "", "deep": 3]]))
        #expect(s.modelRoleAssignments() == ["fast": "a"])
        #expect(s.pinIterations == 210_000)
        #expect(s.pinFailures == 0 && s.pinLockedUntil == 0)
        s.setActiveModelId("llm", "x")
        s.setActiveModelId("llm", nil)
        #expect(s.activeModelId("llm") == nil)
    }

    @Test func jsonValueRoundTripsAndReadsLikeKotlinPrimitives() throws {
        let v = try #require(JSONValue(jsonString: #"{"a":1,"b":[true,null,"x"],"c":{"d":2.5},"e":"7"}"#))
        #expect(v["a"] == .int(1) && v["c"]?["d"] == .double(2.5))
        #expect(v["e"]?.intValue == 7 && v["a"]?.stringValue == nil)
        #expect(JSONValue(jsonString: v.jsonString) == v)
        #expect(JSONValue(jsonString: "{nope") == nil)
        #expect(v["b"]?.arrayValue?.count == 3)
    }
}
