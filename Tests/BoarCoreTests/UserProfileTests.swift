import Foundation
import Testing
@testable import BoarCore

/// Android UserProfileTest (+ ProfileNamesTest's id check, LabDefaultsTest's profile parts). The Kotlin cases about a
/// settings.json that can't be read have no counterpart: the iOS stores never report an unreadable file.
@Suite struct UserProfileTests {
    /// A settings.json path; `text` is written first when given.
    func file(_ text: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("settings.json")
        if let text { try text.write(to: f, atomically: true, encoding: .utf8) }
        return f
    }

    func settings(_ text: String?) throws -> AppSettings { AppSettings(store: JSONFileKeyValueStore(url: try file(text))) }
    func reopened(_ url: URL) -> AppSettings { AppSettings(store: JSONFileKeyValueStore(url: url)) }

    /// An rc2 settings.json: no profile yet.
    static let rc2 = #"{"activeModelId":{"llm":"qwen3-4b"},"personalityId":"detailed","themeId":"moonlight"}"#

    // MARK: gating

    static let simple: Set<SettingsPart> = [.profile, .language, .theme, .textSize, .security, .recovery]
    static let explorer = simple.union([.tone, .memory, .voice, .avatars, .boarverseSwitch, .orientation, .haptics])
    static let pro = Set(SettingsPart.allCases)

    @Test func starterShowsOnlyTheEssentials() {
        #expect(Set(SettingsPart.allCases.filter { $0.shown(in: .simple) }) == Self.simple)
    }

    @Test func explorerAddsAnswersKnowledgeChatsVoiceAndBoarverse() {
        #expect(Set(SettingsPart.allCases.filter { $0.shown(in: .explorer) }) == Self.explorer)
    }

    @Test func proShowsEverything() {
        #expect(Set(SettingsPart.allCases.filter { $0.shown(in: .pro) }) == Self.pro)
    }

    @Test func advancedTweaksTechnicalDetailsTelemetryLabsSettingsAndAdaptiveRoutingAreProOnly() {
        for part in [SettingsPart.tweaks, .technicalDetails, .telemetry, .labsSettings, .adaptiveRouting] {
            #expect(!part.shown(in: .simple))
            #expect(!part.shown(in: .explorer))
            #expect(part.shown(in: .pro))
        }
    }

    @Test func experimentalShowsFromExplorerForTheBoarverseSwitch() {
        #expect(!SettingsPart.experimentalShown(in: .simple))
        #expect(SettingsPart.experimentalShown(in: .explorer))
        #expect(SettingsPart.experimentalShown(in: .pro))
    }

    @Test func theIdSimpleStaysForStarter() {
        #expect(UserProfile.allCases.map(\.key) == ["simple", "explorer", "pro"])
        #expect(UserProfile.default == .simple)
        #expect(UserProfile.of("pro") == .pro)
        #expect(UserProfile.of("starter") == nil)
    }

    /// Android LabDefaultsTest: only Pro manages labs, and a lab left on counts only while Boar Labs is on.
    @Test func onlyProManagesLabs() {
        #expect(!LabDefaults.managementShown(.simple))
        #expect(!LabDefaults.managementShown(.explorer))
        #expect(LabDefaults.managementShown(.pro))
        #expect(LabDefaults.userChoseOn(labsOn: true, stored: [nil, true, false]))
        #expect(!LabDefaults.userChoseOn(labsOn: false, stored: [true]))
        #expect(!LabDefaults.userChoseOn(labsOn: true, stored: [nil, false]))
    }

    // MARK: fresh install and update

    @Test func aFreshInstallStartsOnStarterQuietly() throws {
        let f = try file(nil)
        let s = reopened(f)
        #expect(s.settleProfile(anyLabOn: false) == .simple)
        #expect(s.profileSettled)
        #expect(!s.profileNotePending)
        #expect(reopened(f).userProfile == .simple)
    }

    @Test func openingSettingsWritesNothing() throws {
        let f = try file(nil)
        _ = reopened(f)
        #expect(!FileManager.default.fileExists(atPath: f.path))
    }

    @Test func anInstallWithAnExplorerSettingChangedBecomesExplorer() throws {
        for changed in [#""hapticsEnabled":false"#, #""personalityId":"succinct""#, #""maxTokens":2048"#, #""voiceInputEnabled":false"#,
                        #""autoSummarize":false"#, #""autoGenerateTitles":false"#, #""confirmChatDelete":false"#,
                        #""historyTurnThreshold":12"#, #""maxSavedSessions":50"#] {
            let s = try settings(#"{"activeModelId":{"llm":"m"},\#(changed)}"#)
            #expect(s.settleProfile(anyLabOn: false) == .explorer, "\(changed)")
        }
        #expect(try settings(Self.rc2).settleProfile(anyLabOn: false, boarverseOn: true) == .explorer)
    }

    @Test func explorerSettingsLeftAtTheirDefaultsDontCount() throws {
        let s = try settings(#"""
        {"activeModelId":{"llm":"m"},"hapticsEnabled":true,"personalityId":"detailed","voiceInputEnabled":true,"autoSummarize":true,
        "historyTurnThreshold":6,"maxSavedSessions":10}
        """#)
        #expect(s.settleProfile(anyLabOn: false) == .simple)
    }

    @Test func proWinsOverExplorer() throws {
        let s = try settings(#"{"activeModelId":{"llm":"m"},"hapticsEnabled":false,"engineTweaks":{"threads":4}}"#)
        #expect(s.settleProfile(anyLabOn: false) == .pro)
    }

    @Test func aMissingSettingsFileWithALabOnBecomesProWithTheNote() throws {
        let s = try settings(nil)
        #expect(s.settleProfile(anyLabOn: true) == .pro)
        #expect(s.profileNotePending)
    }

    @Test func anInstallWithNothingChangedBecomesStarterWithTheNote() throws {
        let s = try settings(Self.rc2)
        #expect(!s.profileSettled)
        #expect(s.settleProfile(anyLabOn: false) == .simple)
        #expect(s.profileNotePending)
        s.profileNotePending = false
        #expect(!s.profileNotePending)
    }

    @Test func anInstallWithATweakBecomesPro() throws {
        let s = try settings(#"{"engineTweaks":{"threads":4}}"#)
        #expect(s.settleProfile(anyLabOn: false) == .pro)
        #expect(s.userProfile == .pro)
    }

    @Test func anInstallWithALabOnBecomesPro() throws {
        #expect(try settings(Self.rc2).settleProfile(anyLabOn: true) == .pro)
    }

    @Test func anInstallWithAdaptiveRoutingOrAFreeMemoryDelayOrTheDebugLogBecomesPro() throws {
        #expect(try settings(#"{"adaptiveRoutingEnabled":true}"#).settleProfile(anyLabOn: false) == .pro)
        #expect(try settings(#"{"freeMemoryAfterMinutes":5}"#).settleProfile(anyLabOn: false) == .pro)
        #expect(try settings(#"{"activeModelId":{"llm":"m"},"debugLogEnabled":true}"#).settleProfile(anyLabOn: false) == .pro)
        #expect(try settings(#"{"activeModelId":{"llm":"m"},"debugLogEnabled":false}"#).settleProfile(anyLabOn: false) == .simple)
    }

    @Test func technicalDetailsOnByDefaultIsNotAReasonForPro() throws {
        #expect(try settings(#"{"showLiveStats":true,"themeId":"campfire"}"#).settleProfile(anyLabOn: false) == .simple)
    }

    @Test func theProfileIsSettledOnceAndKept() throws {
        let f = try file(Self.rc2)
        reopened(f).settleProfile(anyLabOn: false)
        let again = reopened(f)
        #expect(again.profileSettled)
        #expect(again.settleProfile(anyLabOn: true) == .simple)
    }

    @Test func beforeItIsSettledAnInstallKeepsItsTweaksAsBefore() throws {
        let s = try settings(#"{"engineTweaks":{"threads":4},"showLiveStats":true}"#)
        #expect(s.engineTweaks.threads == 4)
        #expect(s.showLiveStats)
    }

    @Test func resetSettingsKeepsTheProfile() throws {
        let f = try file(nil)
        let s = reopened(f)
        s.userProfile = .explorer
        s.resetPreferences()
        #expect(reopened(f).userProfile == .explorer)
    }

    // MARK: a lowered profile

    @Test func belowProTheTweaksReadAsAutoAndComeBackWithPro() throws {
        let f = try file(nil)
        let s = reopened(f)
        s.userProfile = .pro
        var tweaks = EngineTweaks()
        tweaks.threads = 6
        tweaks.kvCache = .q8_0
        s.engineTweaks = tweaks
        s.adaptiveRoutingEnabled = true
        s.freeMemoryAfterMinutes = 10
        s.showLiveStats = true
        s.debugLogEnabled = true
        for lower in [UserProfile.simple, .explorer] {
            s.userProfile = lower
            #expect(s.engineTweaks.isAuto)
            #expect(!s.adaptiveRoutingEnabled)
            #expect(s.freeMemoryAfterMinutes == nil)
            #expect(!s.showLiveStats)
            #expect(!s.debugLogEnabled)
        }
        s.userProfile = .pro
        let back = reopened(f)
        #expect(back.engineTweaks == tweaks)
        #expect(back.adaptiveRoutingEnabled)
        #expect(back.freeMemoryAfterMinutes == 10)
        #expect(back.showLiveStats)
        #expect(back.debugLogEnabled)
    }

    @Test func loweringTheProfileDoesntTouchWhatEveryoneSees() throws {
        let s = try settings(nil)
        s.userProfile = .pro
        s.personalityId = "succinct"; s.deepResearchMode = true; s.themeId = "campfire"; s.fontScale = "large"; s.voiceInputEnabled = false
        s.userProfile = .simple
        #expect(s.personalityId == "succinct")
        #expect(s.deepResearchMode)
        #expect(s.themeId == "campfire")
        #expect(s.fontScale == "large")
        #expect(!s.voiceInputEnabled)
    }

    /// Android SettingsDeclutterTest: free memory stays in effect below Pro, the exception to Pro's rule.
    @Test func freeMemoryStaysInEffectBelowPro() throws {
        let s = try settings(nil)
        s.userProfile = .pro
        s.freeMemoryInBackground = false
        s.userProfile = .simple
        #expect(!s.freeMemoryInBackground)
        #expect(try settings(nil).freeMemoryInBackground)
    }
}
