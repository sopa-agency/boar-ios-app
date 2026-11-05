import Foundation

/// Boar Nomad's arithmetic (android labs/plugins/compass `CompassLab.kt`), pure so it is tested on the Mac host: the
/// shown heading follows the sensor's along the shortest way round, the number moves in whole degrees only once the
/// heading has moved at least 1°, and the eight cardinal directions are 45° wide.
public enum CompassMath {
    /// How much of each new reading goes into the shown heading: smooth enough to read, quick enough to follow.
    public static let smoothing = 0.15

    /// The heading after a new `reading` (degrees, 0..<360): the first one is taken as it is; later ones move the heading
    /// by `smoothing` of the shortest way round, so 359° → 1° doesn't swing through 180°.
    public static func follow(_ heading: Double, reading: Double, first: Bool) -> Double {
        if first { return reading }
        let delta = (reading - heading + 540).truncatingRemainder(dividingBy: 360) - 180
        return (heading + smoothing * delta + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The whole degree to show: `previous` until the heading is at least 1° away from it, so the number doesn't flicker
    /// between two values while the phone is still.
    public static func shown(_ heading: Double, previous: Int) -> Int {
        let away = abs((heading - Double(previous) + 540).truncatingRemainder(dividingBy: 360) - 180)
        if away < 1 { return previous }
        // Kotlin roundToInt: half up.
        return Int((heading + 0.5).rounded(.down)) % 360
    }

    /// "n", "ne", "e"… for the 8 directions, each 45° wide.
    public static func cardinal(_ deg: Int) -> String {
        ["n", "ne", "e", "se", "s", "sw", "w", "nw"][((deg + 22) % 360) / 45]
    }
}
