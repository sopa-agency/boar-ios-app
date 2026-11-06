import Foundation
import Testing

@testable import BoarAnswer

/// MoonPhase (Boar Lunar) against the values its Kotlin source cites: Meeus's example 49.a and October 2026. Android
/// has no unit test for it; these pin the port to the same numbers.
struct MoonPhaseTests {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int64 {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (y, mo, d, h, mi)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return Int64(cal.date(from: c)!.timeIntervalSince1970 * 1000)
    }

    @Test func meeusExample49aNewMoonOf1977Feb18() {
        // Meeus 49.a: k = -283, JDE 2443192.65118 (1977 Feb 18 03:37:42 TD). Without the planetary terms this gives
        // 2443192.65189, 1.02 minutes later (the Kotlin comment's "within a minute" is rounded; same formula).
        let jd = MoonPhase.phaseJd(-283, full: false)
        #expect(abs(jd - 2443192.65118) * 1440 < 2, "\(jd)")
    }

    @Test func october2026NewAndFullMoonWithinTwoMinutes() {
        let s = MoonPhase.at(utc(2026, 10, 5, 12, 0))
        #expect(abs(s.nextNewMs - utc(2026, 10, 10, 15, 51)) < 120_000)
        let after = MoonPhase.at(utc(2026, 10, 12, 0, 0))
        #expect(abs(after.lastNewMs - utc(2026, 10, 10, 15, 51)) < 120_000)
        #expect(abs(after.nextFullMs - utc(2026, 10, 26, 4, 12)) < 120_000)
    }

    @Test func phasesThroughOctober2026() {
        // Full moon on the 26th, new on the 10th; a day either side keeps the name.
        let full = MoonPhase.at(utc(2026, 10, 26, 4, 12))
        #expect(MoonPhase.nameKey(full) == "full")
        #expect(full.illumination > 0.99)
        let new = MoonPhase.at(utc(2026, 10, 10, 20, 0))
        #expect(MoonPhase.nameKey(new) == "new")
        #expect(new.illumination < 0.01)
        #expect(MoonPhase.nameKey(MoonPhase.at(utc(2026, 10, 13, 12, 0))) == "waxingCrescent")
        #expect(MoonPhase.nameKey(MoonPhase.at(utc(2026, 10, 30, 12, 0))) == "waningGibbous")
    }

    @Test func southMirrorsTheDrawing() {
        let s = MoonPhase.at(utc(2026, 10, 13, 12, 0))
        #expect(MoonPhase.emoji(s, south: false) == "🌒")
        #expect(MoonPhase.emoji(s, south: true) == "🌘")
        let full = MoonPhase.at(utc(2026, 10, 26, 4, 12))
        #expect(MoonPhase.emoji(full, south: false) == MoonPhase.emoji(full, south: true))
    }

    @Test func stateIsConsistentAcrossAYear() {
        var t = utc(2026, 1, 1, 0, 0)
        for _ in 0..<365 {
            let s = MoonPhase.at(t)
            #expect(s.ageDays >= 0 && s.ageDays < s.lengthDays)
            #expect(s.lengthDays > 29.2 && s.lengthDays < 29.9)
            #expect(s.lastNewMs <= t && t < s.nextNewMs && t < s.nextFullMs)
            t += 86_400_000
        }
    }
}
