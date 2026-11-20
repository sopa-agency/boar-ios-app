import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// Staged answers became core on Nov 12 (adam): a setting, on by default (android StagedCoreTest, GuardChecksStagedTest).
struct StagedCoreTests {
    @Test func onByDefaultAndAStoredOffHolds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-staged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("settings.json")
        let s = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(s.stagedQuotes)
        s.stagedQuotes = false
        #expect(!AppSettings(store: JSONFileKeyValueStore(url: f)).stagedQuotes)
        // Reset settings brings the default back, as on Android (PREFERENCE_KEYS).
        s.resetPreferences()
        #expect(AppSettings(store: JSONFileKeyValueStore(url: f)).stagedQuotes)
        try? FileManager.default.removeItem(at: dir)
    }

    /// adam, Nov 14: Staged is the main answer style, so the check slot (Guard) reads Staged answers too.
    @Test func normalAdaptiveAndStagedAnswersAreCheckedDeepResearchAndRecapsAreNot() {
        for path in [nil, "adaptive", "staged"] as [String?] {
            #expect(LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: path, blank: false), "\(path ?? "nil")")
        }
        for path in ["deep", "chat"] {
            #expect(!LabTools.checksAnswer(instant: false, stopped: false, timedOut: false, failed: false, path: path, blank: false), "\(path)")
        }
        #expect(!LabTools.checksAnswer(instant: false, stopped: true, timedOut: false, failed: false, path: "staged", blank: false))
        #expect(!LabTools.checksAnswer(instant: true, stopped: false, timedOut: false, failed: false, path: "staged", blank: false))
    }

    @Test func theIndiaAnswerFromAdamsStagedChatIsCorrected() {
        let fixed = LabTools.guard(
            question: "Which countries are bigger than India?",
            answer: "No countries are bigger than India by area. India is the world's seventh-largest country by area."
        )
        #expect(fixed?.text.hasPrefix("Six countries are bigger than India") == true, "\(fixed?.text ?? "")")
    }
}
