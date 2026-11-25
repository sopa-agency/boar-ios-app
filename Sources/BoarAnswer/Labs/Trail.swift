import Foundation

/// The waiting animation next to the matrix rain (android engine/labs `Trail.kt`, rc3 slice 4 bfe69c4b; adam, Nov 10): a
/// boar trots across the screen and leaves hoofprints that fade behind it, then comes round again. Positions only, in 0...1
/// of the drawing area, so a screen draws it at any size and the math is tested here.
///
/// On Android it runs on the Close BOAR screen (hoofprints only, 50bdf593). iOS has no such screen (an iOS app doesn't
/// quit itself) and Designer waits on Image Playground's own progress, so no iOS screen draws it yet (docs/labs-ios.md).
public enum Trail {
    /// One crossing, in seconds.
    public static let period = 6.0
    /// A print every this many seconds, so about 12 per crossing.
    public static let step = 0.5
    /// A print fades out over this many seconds.
    public static let fade = 4.0

    /// Where the boar is: `x` left to right, `y` a slight bob (it crosses one way).
    public struct Boar: Sendable, Equatable {
        public let x: Float
        public let y: Float
    }

    /// One hoofprint: where, which side of the track (alternating), and how faded (1 new, 0 gone).
    public struct Print: Sendable, Equatable {
        public let x: Float
        public let y: Float
        public let upper: Bool
        public let alpha: Float
    }

    public struct Frame: Sendable, Equatable {
        public let boar: Boar
        public let prints: [Print]
    }

    /// The track's height in the drawing area.
    private static let trackY: Float = 0.62
    private static let bob: Float = 0.015
    private static let spread: Float = 0.035

    /// Kotlin `Double % Double` (truncated, sign of the dividend), as `truncatingRemainder`.
    private static func rem(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

    /// The frame at `seconds`. `still`: the device's motion is reduced, so one calm frame: the boar mid-way, its prints so
    /// far, none fading.
    public static func at(_ seconds: Double, still: Bool = false) -> Frame {
        let t = still ? period / 2 : seconds
        let phase = rem(rem(t, period) + period, period) / period
        let boar = Boar(x: Float(-0.1 + 1.2 * phase), y: Float(Double(trackY) - 0.05 + (still ? 0.0 : Double(bob) * sin(t * 8))))
        var prints: [Print] = []
        let last = Int64((t / step).rounded(.down))
        let count = Int(fade / step)
        for k in 0...count {
            let n = last - Int64(k)
            if n < 0 { break }
            let made = Double(n) * step
            let age = t - made
            let alpha: Float = still ? 1 : Float(1 - age / fade)
            if alpha <= 0 { continue }
            let p = rem(rem(made, period) + period, period) / period
            let x = Float(-0.1 + 1.2 * p)
            // Only prints of this crossing: a print from the last crossing ahead of the boar would read as a wrong way.
            if x > boar.x || x < 0 || x > 1 { continue }
            let upper = n % 2 == 0
            prints.append(Print(x: x, y: trackY + (upper ? -spread : spread), upper: upper, alpha: min(max(alpha, 0), 1)))
        }
        return Frame(boar: boar, prints: prints)
    }
}
