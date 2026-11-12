@testable import BoarCore
import Foundation
import Testing

/// The app's counting (android `TruffleVault.onOpen`, `answered`, the Daily Quiz's record) and the stored state's key.
struct VaultCountingTests {
    typealias Day = Vault.Day
    typealias Counting = Vault.Counting
    let today = Day(year: 2026, month: 11, day: 11)

    private func opened(_ f: Vault.Facts = Vault.Facts(), day: Day? = nil, noNetwork: Bool = false, pinOn: Bool = false,
                        packs: Int = 0, hfModels: Int = 0, sourceBuild: Bool = false, degoogled: Bool = false) -> Vault.Facts {
        Counting.opened(f, today: day ?? today, noNetwork: noNetwork, pinOn: pinOn, packs: packs, hfModels: hfModels,
                        sourceBuild: sourceBuild, degoogled: degoogled)
    }

    @Test func openingCountsTheDayOnceAndANoNetworkDayOnlyWithoutNetwork() {
        var f = opened()
        #expect(f.usedDays == ["2026-11-11"] && f.airplaneDays.isEmpty)
        f = opened(f)
        #expect(f.usedDays == ["2026-11-11"])
        f = opened(f, noNetwork: true)
        f = opened(f, day: today.minusDays(-1), noNetwork: true)
        #expect(f.usedDays == ["2026-11-11", "2026-11-12"])
        #expect(f.airplaneDays == ["2026-11-11", "2026-11-12"])
    }

    @Test func openingOnlyTurnsFlagsOnAndOnlyRaisesCounts() {
        var f = opened(pinOn: true, packs: 2, hfModels: 3, sourceBuild: true, degoogled: true)
        #expect(f.pinOn && f.sourceBuild && f.degoogled && f.packs == 2 && f.hfModels == 3)
        // The lock turned off, a pack and a model removed: what was counted stays.
        f = opened(f, packs: 1, hfModels: 0)
        #expect(f.pinOn && f.sourceBuild && f.degoogled && f.packs == 2 && f.hfModels == 3)
        f = opened(f, packs: 4)
        #expect(f.packs == 4)
    }

    @Test func everyDeviceIsDeGoogledSoStealthAndTacticalUnlockAtTheFirstOpen() {
        let f = opened(degoogled: true)
        let (_, fresh) = Vault.apply(Vault.State(), facts: f, today: today, now: 1)
        #expect(fresh == ["tactical", "stealth"])
        #expect(Counting.announced(fresh) == ["stealth"])
    }

    @Test func aLockedAppOpenedWithNoNetworkUnlocksTheDarkTacticalBoar() {
        let f = opened(noNetwork: true, pinOn: true)
        let fresh = Vault.apply(Vault.State(), facts: f, today: today, now: 1).fresh
        #expect(fresh.contains("tactical_ii") && fresh.contains("tactical_city"))
    }

    @Test func anAnswerCountsWhatItWas() {
        var f = Counting.answered(Vault.Facts(), sourced: true, deep: false, portuguese: false, tokPerSec: 9.5, newChat: true,
                                  offline: false, night: false)
        #expect(f.answers == 1 && f.sourcedAnswers == 1 && f.chats == 1 && f.bestTokPerSec == 9.5)
        #expect(f.offlineAnswers == 0 && f.nightAnswers == 0 && f.deepResearch == 0 && !f.portuguese)
        f = Counting.answered(f, sourced: false, deep: true, portuguese: true, tokPerSec: nil, newChat: false, offline: true, night: true)
        #expect(f.answers == 2 && f.sourcedAnswers == 1 && f.chats == 1)
        #expect(f.offlineAnswers == 1 && f.nightAnswers == 1 && f.deepResearch == 1 && f.portuguese)
        // An instant answer (no speed) or a slower one never lowers the best speed.
        #expect(f.bestTokPerSec == 9.5)
        f = Counting.answered(f, sourced: false, deep: false, portuguese: false, tokPerSec: 4, newChat: false, offline: false, night: false)
        #expect(f.bestTokPerSec == 9.5 && f.portuguese)
    }

    @Test func theQuizCountsRightAnswersAndEachDayOnce() {
        var f = Counting.quizAnswered(Vault.Facts(), right: true, day: today)
        f = Counting.quizAnswered(f, right: false, day: today)
        f = Counting.quizAnswered(f, right: true, day: today.minusDays(1))
        #expect(f.quizRight == 2)
        #expect(f.quizDays == ["2026-11-10", "2026-11-11"])
    }

    @Test func onlyTheStartingAvatarIsLeftOutOfTheAnnouncement() {
        #expect(Counting.announced(["tactical", "cosmo", "fomo_unicorn"]) == ["cosmo", "fomo_unicorn"])
        #expect(Counting.announced([]).isEmpty)
    }

    @Test func theStateIsStoredAsAJsonObjectUnderTruffleVault() throws {
        let s = AppSettings(store: InMemoryKeyValueStore())
        #expect(s.truffleVault == nil)
        let state = Vault.State(facts: Vault.Facts(answers: 3, bestTokPerSec: 14, usedDays: ["2026-11-11"]),
                                unlocked: ["tactical": 1_762_819_200_000])
        s.truffleVault = Vault.toJson(state)
        #expect(s.raw()["truffleVault"]?.objectValue != nil)
        #expect(s.raw()["truffleVault"]?["unlocked"]?["tactical"] == .int(1_762_819_200_000))
        #expect(Vault.fromJson(s.truffleVault) == state)
        // A string, or junk, isn't a vault: nothing is read back.
        s.setJSONValue(.string("{}"), forKey: "truffleVault")
        #expect(s.truffleVault == nil)
        s.truffleVault = "{nope"
        #expect(s.raw()["truffleVault"] == nil)
    }
}
