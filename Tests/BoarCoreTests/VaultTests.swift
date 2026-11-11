@testable import BoarCore
import Foundation
import Testing

/// Android's engine/vault `VaultTest.kt`, test for test, plus the date and JSON details the Swift port adds.
struct VaultTests {
    typealias Day = Vault.Day
    let today = Day(year: 2026, month: 10, day: 13)

    static func day(_ s: String) -> Day { Day(iso: s)! }

    @Test func everyIconInTheArtRosterHasARuleAndEveryRuleAnIcon() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/vault/truffles.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let icons = try #require(obj["icons"] as? [[String: Any]])
        let roster = icons.compactMap { $0["id"] as? String }
        #expect(roster == Vault.rules.map(\.id))
    }

    @Test func aFreshInstallHasOnlyTheDefaultTruffle() {
        let (state, fresh) = Vault.apply(Vault.State(), facts: Vault.Facts(), today: today, now: 1)
        #expect(fresh == ["tactical"])
        #expect(state.unlocked == ["tactical": 1])
    }

    @Test func thresholdsUnlockOnceAndKeepTheirFirstDate() {
        var state = Vault.apply(Vault.State(), facts: Vault.Facts(), today: today, now: 1).state
        let first = Vault.apply(state, facts: Vault.Facts(answers: 10), today: today, now: 2)
        #expect(first.fresh == ["cosmo", "solarpunk"])
        state = first.state
        let again = Vault.apply(state, facts: Vault.Facts(answers: 11), today: today, now: 3)
        #expect(again.fresh.isEmpty)
        #expect(again.state.unlocked["cosmo"] == 2)
        #expect(again.state.unlocked["planter"] == nil)
    }

    @Test func theUnicornIsLegendaryTheLastOneOnceEveryOtherTruffleIsOut() {
        var allButUnicorn: [String: Int64] = [:]
        for (id, _) in Vault.rules where id != "fomo_unicorn" { allButUnicorn[id] = 1 }
        var almostUnlocked = allButUnicorn
        almostUnlocked["cosmo"] = nil
        let almost = Vault.State(unlocked: almostUnlocked)
        let (s1, f1) = Vault.apply(almost, facts: Vault.Facts(), today: today, now: 2)
        #expect(f1.isEmpty)
        #expect(s1.unlocked["fomo_unicorn"] == nil)
        let (s2, f2) = Vault.apply(almost, facts: Vault.Facts(answers: 1), today: today, now: 3)
        #expect(f2 == ["cosmo", "fomo_unicorn"])
        #expect(s2.unlocked["fomo_unicorn"] == 3)
    }

    @Test func quantumNeedsMoreThan15TokPerSVolcanic8() {
        #expect(!Vault.Rule.FAST_15.test(Vault.Facts(bestTokPerSec: 15.0), today))
        #expect(Vault.Rule.FAST_15.test(Vault.Facts(bestTokPerSec: 15.1), today))
        #expect(Vault.Rule.FAST_8.test(Vault.Facts(bestTokPerSec: 8.0), today))
    }

    @Test func anAirplaneStreakCountsDaysInARowEndingTodayOrYesterday() {
        var days: [String] = []
        for s in ["2026-10-07", "2026-10-08", "2026-10-09", "2026-10-11", "2026-10-12"] { days = Vault.Days.add(days, Self.day(s)) }
        #expect(Vault.Days.streak(days, today) == 2) // 11th and 12th; today not opened yet
        #expect(Vault.Days.streak(Vault.Days.add(days, today), today) == 3)
        #expect(Vault.Days.streak(days, Self.day("2026-10-15")) == 0)
        #expect(!Vault.Rule.AIRPLANE_STREAK_3.test(Vault.Facts(airplaneDays: days), today))
        #expect(Vault.Rule.AIRPLANE_STREAK_3.test(Vault.Facts(airplaneDays: Vault.Days.add(days, today)), today))
    }

    @Test func dayListsStayDistinctSortedAndBounded() {
        var days: [String] = []
        for _ in 0..<3 { days = Vault.Days.add(days, today) }
        #expect(days == ["2026-10-13"])
        for i in 1...100 { days = Vault.Days.add(days, today.minusDays(Int64(i))) }
        #expect(days.count == Vault.Days.keep)
        #expect(days.last == "2026-10-13")
        #expect(days == days.sorted())
    }

    @Test func nightIs0200To0359() {
        #expect((0...23).filter { Vault.isNight(hour: $0) } == [2, 3])
    }

    @Test func stateRoundTripsThroughJSONAndSurvivesJunk() {
        let s = Vault.State(facts: Vault.Facts(answers: 3, usedDays: ["2026-10-13"]), unlocked: ["cosmo": 5], themes: ["hacker_green": 7])
        #expect(Vault.fromJson(Vault.toJson(s)) == s)
        #expect(Vault.fromJson("not json") == Vault.State())
        #expect(Vault.fromJson(nil) == Vault.State())
    }

    // The Daily Quiz lab unlocks knight and elder (Oct 24).
    @Test func aFirstRightQuizAnswerUnlocksKnightSevenQuizDaysElder() {
        let d = Day(year: 2026, month: 10, day: 24)
        let (one, fresh) = Vault.apply(Vault.State(), facts: Vault.Facts(quizRight: 1), today: d, now: 1)
        #expect(fresh.contains("knight"), "\(fresh)")
        #expect(one.unlocked["elder"] == nil)
        let days = (0..<7).map { d.minusDays(Int64($0)).description }
        let later = Vault.apply(one, facts: Vault.Facts(quizRight: 1, quizDays: days), today: d, now: 2).fresh
        #expect(later.contains("elder"), "\(later)")
    }

    @Test func aVaultStoredBeforeTheQuizStillLoadsAndKeepsWhatItHad() {
        let old = #"{"facts":{"answers":12,"evalShares":1},"unlocked":{"knight":5,"cosmo":3}}"#
        let s = Vault.fromJson(old)
        #expect(s.facts.answers == 12)
        #expect(s.facts.quizRight == 0)
        #expect(s.unlocked["knight"] == 5)
    }

    @Test func knightAndElderBelongToTheDailyQuiz() {
        #expect(Vault.rule("knight") == .QUIZ_FIRST)
        #expect(Vault.rule("elder") == .QUIZ_DAYS_7)
        #expect(!Vault.rules.contains { $0.rule == .EVAL_SHARED || $0.rule == .EXPORT })
    }

    // Swift-only checks: what java.time and kotlinx.serialization give Android for free.

    @Test func daysMatchJavaTime() {
        #expect(Day(year: 1970, month: 1, day: 1).epochDay == 0)
        #expect(Day(year: 2026, month: 10, day: 13).epochDay == 20739)
        #expect(Day(year: 2000, month: 2, day: 29).description == "2000-02-29")
        #expect(Day(year: 2026, month: 3, day: 1).minusDays(1).description == "2026-02-28")
        #expect(Day(year: 2024, month: 3, day: 1).minusDays(1).description == "2024-02-29")
        #expect(Day(year: 2027, month: 1, day: 1).minusDays(1).description == "2026-12-31")
        #expect(Day(iso: "2026-13-01") == nil)
        #expect(Day(iso: "junk") == nil)
        // LocalDate.parse rejects both.
        #expect(Day(iso: "2026-02-31") == nil)
        #expect(Day(iso: "2026-+1-05") == nil)
        #expect(Day(iso: "2024-02-29") != nil)
        for n in stride(from: Int64(-1000), through: 40000, by: 37) {
            let d = Day(epochDay: n)
            #expect(Day(iso: d.description) == d)
        }
    }

    @Test func todayFollowsTheTimeZone() throws {
        let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        // 02:30 UTC on Nov 11 is 23:30 on Nov 10 in São Paulo.
        let instant = Date(timeIntervalSince1970: 1_794_364_200)
        #expect(Day.today(instant, timeZone: saoPaulo).description == "2026-11-10")
        #expect(Day.today(instant, timeZone: try #require(TimeZone(identifier: "UTC"))).description == "2026-11-11")
    }

    @Test func jsonLeavesDefaultsOutLikeAndroid() {
        #expect(Vault.toJson(Vault.State()) == "{}")
        #expect(Vault.toJson(Vault.State(facts: Vault.Facts(answers: 2))) == #"{"facts":{"answers":2}}"#)
        // A wrong type is junk, as runCatching makes it on Android.
        #expect(Vault.fromJson(#"{"facts":{"answers":"x"}}"#) == Vault.State())
        // Unknown keys are ignored (ignoreUnknownKeys).
        #expect(Vault.fromJson(#"{"facts":{"answers":4,"newFact":1},"later":true}"#).facts.answers == 4)
    }

    @Test func everyRuleHasAName() {
        #expect(Vault.Rule.allCases.count == 43)
        #expect(Set(Vault.rules.map(\.id)).count == 40)
    }
}
