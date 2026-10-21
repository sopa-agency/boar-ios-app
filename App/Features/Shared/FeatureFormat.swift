import Foundation

/// Sizes, speeds and times as the screens print them. Sizes use the iOS file style (decimal, as Settings shows them).
enum FeatureFormat {
    /// A size as iOS Settings prints it (decimal: "2.5 GB", "37 MB").
    static func megabytes(_ bytes: Int64) -> String {
        max(bytes, 0).formatted(.byteCount(style: .file))
    }

    static func speed(_ bytesPerSecond: Double?) -> String? {
        guard let b = bytesPerSecond, b > 0 else { return nil }
        if b >= 1024 * 1024 { return String(format: "%.1f MB/s", locale: .init(identifier: "en_US_POSIX"), b / 1_048_576) }
        return String(format: "%.0f KB/s", locale: .init(identifier: "en_US_POSIX"), b / 1024)
    }

    /// Time left in whole minutes or hours ("3 min", "1 hr, 5 min"); under a minute reads "1 min".
    static func eta(_ seconds: Double?) -> String? {
        guard let s = seconds, s > 0, s.isFinite else { return nil }
        let minutes = max(1, (s / 60).rounded(.up))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// Same as `megabytes`: one size format everywhere.
    static func gigabytes(_ bytes: Int64) -> String {
        max(bytes, 0).formatted(.byteCount(style: .file))
    }

    /// "850 ms" under a second, "2.4 s" above (EvaluationScreen.kt formatMs).
    static func milliseconds(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        if ms < 1000 { return String(format: "%.0f ms", locale: .init(identifier: "en_US_POSIX"), ms) }
        return String(format: "%.1f s", locale: .init(identifier: "en_US_POSIX"), ms / 1000)
    }
}
