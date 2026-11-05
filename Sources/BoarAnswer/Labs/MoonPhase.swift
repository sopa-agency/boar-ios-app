import Foundation

/// Boar Lunar's moon (android labs/plugins/lunar `MoonPhase.kt`): phases from the date alone, offline: Meeus,
/// Astronomical Algorithms ch. 49 (true new and full moon with the main periodic terms; the planetary terms, under a
/// minute, are left out). Checked against Meeus's example 49.a (new moon 1977 Feb 18 03:37 TD, within a minute) and Oct
/// 2026 (new 10 Oct 15:51, full 26 Oct 04:12 UTC). Times are UTC.
///
/// Lives in BoarAnswer, not with the lab's page as on Android, so its tests run on the Mac host.
public enum MoonPhase {
    private static let synodic = 29.530588861
    private static let j2000New = 2451550.09766
    private static let unixEpochJd = 2440587.5

    public static func julianDay(_ epochMs: Int64) -> Double { Double(epochMs) / 86_400_000.0 + unixEpochJd }
    public static func epochMs(_ jd: Double) -> Int64 { Int64((jd - unixEpochJd) * 86_400_000.0) }

    /// The new moon (k a whole number) or full moon (k + 0.5) for lunation `k` counted from Jan 2000, as a Julian day.
    public static func phaseJd(_ k: Double, full: Bool) -> Double {
        let t = k / 1236.85
        let jde = j2000New + synodic * k + 0.00015437 * t * t - 0.000000150 * t * t * t + 0.00000000073 * t * t * t * t
        let e = 1 - 0.002516 * t - 0.0000074 * t * t
        func r(_ d: Double) -> Double { d * .pi / 180 }
        let m = r(2.5534 + 29.10535670 * k - 0.0000014 * t * t - 0.00000011 * t * t * t)
        let mp = r(201.5643 + 385.81693528 * k + 0.0107582 * t * t + 0.00001238 * t * t * t - 0.000000058 * t * t * t * t)
        let f = r(160.7108 + 390.67050284 * k - 0.0016118 * t * t - 0.00000227 * t * t * t + 0.000000011 * t * t * t * t)
        let o = r(124.7746 - 1.56375588 * k + 0.0020672 * t * t + 0.00000215 * t * t * t)
        let c = full
            ? [-0.40614, 0.17302, 0.01614, 0.01043, 0.00734, -0.00515, 0.00209]
            : [-0.40720, 0.17241, 0.01608, 0.01039, 0.00739, -0.00514, 0.00208]
        var sum = jde + c[0] * sin(mp) + c[1] * e * sin(m) + c[2] * sin(2 * mp) + c[3] * sin(2 * f) + c[4] * e * sin(mp - m)
        sum += c[5] * e * sin(mp + m) + c[6] * e * e * sin(2 * m) - 0.00111 * sin(mp - 2 * f) - 0.00057 * sin(mp + 2 * f)
        sum += 0.00056 * e * sin(2 * mp + m) - 0.00042 * sin(3 * mp) + 0.00042 * e * sin(m + 2 * f) + 0.00038 * e * sin(m - 2 * f)
        sum += -0.00024 * e * sin(2 * mp - m) - 0.00017 * sin(o)
        return sum
    }

    /// The moon at an instant: days since the last new moon, the lunation's length, the lit fraction, the phase (0..1).
    public struct State: Sendable, Equatable {
        public let ageDays: Double, lengthDays: Double, illumination: Double, phase: Double
        public let lastNewMs: Int64, nextNewMs: Int64, nextFullMs: Int64
    }

    public static func at(_ epochMs: Int64) -> State {
        let jd = julianDay(epochMs)
        var k = ((jd - j2000New) / synodic).rounded(.down)
        while phaseJd(k, full: false) > jd { k -= 1 }
        while phaseJd(k + 1, full: false) <= jd { k += 1 }
        let lastNew = phaseJd(k, full: false)
        let nextNew = phaseJd(k + 1, full: false)
        let full = phaseJd(k + 0.5, full: true)
        let nextFull = full > jd ? full : phaseJd(k + 1.5, full: true)
        let age = jd - lastNew
        let length = nextNew - lastNew
        let phase = age / length
        return State(ageDays: age, lengthDays: length, illumination: (1 - cos(2 * .pi * phase)) / 2, phase: phase,
                     lastNewMs: Self.epochMs(lastNew), nextNewMs: Self.epochMs(nextNew), nextFullMs: Self.epochMs(nextFull))
    }

    public static func at(_ date: Date) -> State { at(Int64((date.timeIntervalSince1970 * 1000).rounded(.down))) }

    /// Which of the eight phases `s` is in: new, first quarter, full and last quarter within a day of their moment, the
    /// crescents and gibbous moons between. Equal eighths named day 5.9 (34 % lit) "first quarter" (X6, Oct 16).
    public static func index(_ s: State) -> Int {
        let q = s.lengthDays / 4
        func near(_ day: Double) -> Bool { abs(s.ageDays - day) < 1.0 }
        if s.ageDays < 1.0 || s.ageDays > s.lengthDays - 1.0 { return 0 }
        if near(q) { return 2 }
        if near(2 * q) { return 4 }
        if near(3 * q) { return 6 }
        if s.ageDays < q { return 1 }
        if s.ageDays < 2 * q { return 3 }
        if s.ageDays < 3 * q { return 5 }
        return 7
    }

    public static func nameKey(_ s: State) -> String { keys[index(s)] }

    /// The phase as an emoji, drawn as seen from the north; `south` mirrors it (a waxing moon is lit on the left there).
    public static func emoji(_ s: State, south: Bool) -> String { (south ? southEmoji : northEmoji)[index(s)] }

    private static let keys = ["new", "waxingCrescent", "firstQuarter", "waxingGibbous", "full", "waningGibbous", "lastQuarter", "waningCrescent"]
    private static let northEmoji = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
    private static let southEmoji = ["🌑", "🌘", "🌗", "🌖", "🌕", "🌔", "🌓", "🌒"]
}
