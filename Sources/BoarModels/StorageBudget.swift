import Foundation

/// Whether a download fits: within BOAR's 50 GB budget for the app and its offline assets, and within the phone's free
/// space (port of `StorageBudget.kt`).
public enum StorageBudget {
    /// Room kept for the app itself (the bundle, runtime files), which isn't measured on disk here.
    public static let appReserveBytes: Int64 = 1_000_000_000
    /// Free space to leave on the phone after a download.
    public static let freeSpaceMarginBytes: Int64 = 500_000_000

    public struct Input: Sendable, Equatable {
        public var usedBytes: Int64
        public var reservedBytes: Int64
        public var downloadBytes: Int64
        public var alreadyDownloadedBytes: Int64
        /// nil when unknown.
        public var freeDiskBytes: Int64?
        public var budgetBytes: Int64

        public init(usedBytes: Int64, reservedBytes: Int64, downloadBytes: Int64, alreadyDownloadedBytes: Int64, freeDiskBytes: Int64?, budgetBytes: Int64) {
            self.usedBytes = usedBytes
            self.reservedBytes = reservedBytes
            self.downloadBytes = downloadBytes
            self.alreadyDownloadedBytes = alreadyDownloadedBytes
            self.freeDiskBytes = freeDiskBytes
            self.budgetBytes = budgetBytes
        }
    }

    public enum Reason: Sendable, Equatable { case budget, disk }

    public enum Check: Sendable, Equatable {
        case ok(projectedBytes: Int64)
        case refused(reason: Reason, projectedBytes: Int64, message: String)

        public var projectedBytes: Int64 {
            switch self {
            case .ok(let p), .refused(_, let p, _): return p
            }
        }

        public var isOk: Bool { if case .ok = self { return true } else { return false } }
    }

    public static func check(_ input: Input) -> Check {
        let projected = appReserveBytes + input.usedBytes + input.reservedBytes + input.downloadBytes
        if projected > input.budgetBytes {
            return .refused(
                reason: .budget, projectedBytes: projected,
                message: "Not enough room in BOAR's \(Units.formatBytes(input.budgetBytes)) storage budget: this \(Units.formatBytes(input.downloadBytes)) download " +
                    "would bring the total to about \(Units.formatBytes(projected)). Remove a model first.")
        }
        let stillNeeded = max(input.downloadBytes - input.alreadyDownloadedBytes, 0)
        if let free = input.freeDiskBytes, stillNeeded + freeSpaceMarginBytes > free {
            return .refused(
                reason: .disk, projectedBytes: projected,
                message: "Not enough free space on this phone: the download needs \(Units.formatBytes(stillNeeded)) and only " +
                    "\(Units.formatBytes(free)) is free. Free up space or remove a model first.")
        }
        return .ok(projectedBytes: projected)
    }
}
