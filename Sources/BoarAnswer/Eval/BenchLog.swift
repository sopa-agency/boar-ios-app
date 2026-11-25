/// The bench's log as the Benchmark screen shows it (android `BenchLog`, adam, Nov 12): newest line first, the last
/// `max` lines, and a clock since the last line under the heading so a long answer doesn't look stuck.
public enum BenchLog {
    public static let max = 60

    /// The last `max` lines, newest first.
    public static func newestFirst(_ lines: [String]) -> [String] { Array(lines.suffix(max).reversed()) }

    /// Time since the last line as Android says it: seconds under a minute, else minutes and seconds.
    public static func since(ms: Int64) -> (minutes: Int64?, seconds: Int64) {
        let s = Swift.max(0, ms / 1000)
        return s < 60 ? (nil, s) : (s / 60, s % 60)
    }
}
