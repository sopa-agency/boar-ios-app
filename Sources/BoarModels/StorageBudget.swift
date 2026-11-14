import Foundation
import os

/// Whether a download fits: within BOAR's 50 GB budget for the app and its offline assets, and within the phone's free
/// space (port of `StorageBudget.kt`).
public enum StorageBudget {
    /// Room kept for the app itself (the bundle, runtime files), which isn't measured on disk here.
    public static let appReserveBytes: Int64 = 1_000_000_000
    /// Free space to leave on the phone after a download.
    public static let freeSpaceMarginBytes: Int64 = 500_000_000

    /// No BOAR limit: only the phone's free space counts.
    public static let noLimit: Int64 = .max

    private static let userLimitHook = OSAllocatedUnfairLock<(@Sendable () -> Int64?)?>(initialState: nil)

    /// The user's own limit (Boar Labs, in Advanced); nil, or a nil answer, keeps the catalog's 50 GB.
    public static var userLimit: (@Sendable () -> Int64?)? {
        get { userLimitHook.withLock { $0 } }
        set { userLimitHook.withLock { $0 = newValue } }
    }

    /// The limit in force: the user's, else `catalogBudget`.
    public static func limit(catalogBudget: Int64) -> Int64 { limit(catalogBudget: catalogBudget, user: userLimit?()) }

    static func limit(catalogBudget: Int64, user: Int64?) -> Int64 { user ?? catalogBudget }

    /// The Labs choice as bytes (android `LabHooks.storageLimitBytes`): "auto" or unknown, nil (the catalog's 50 GB);
    /// "none", `noLimit`; else that many GB.
    public static func limitBytes(choice: String?) -> Int64? {
        switch choice {
        case nil, "auto": return nil
        case "none": return noLimit
        default: return choice.flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 * 1_000_000_000 : nil }
        }
    }

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

    /// Why a download can't start, with the numbers the error texts fill in. `usedBytes`: what BOAR already holds on disk;
    /// `downloadingBytes`: the full size of other downloads running; `neededBytes`: what this download still has to
    /// fetch; `freeDiskBytes`: the phone's free space, when known.
    public struct Refused: Sendable, Equatable {
        public var reason: Reason
        public var projectedBytes: Int64
        public var message: String
        public var budgetBytes: Int64 = 0
        public var usedBytes: Int64 = 0
        public var downloadingBytes: Int64 = 0
        public var neededBytes: Int64 = 0
        public var freeDiskBytes: Int64?

        public init(reason: Reason, projectedBytes: Int64, message: String, budgetBytes: Int64 = 0, usedBytes: Int64 = 0,
                    downloadingBytes: Int64 = 0, neededBytes: Int64 = 0, freeDiskBytes: Int64? = nil) {
            self.reason = reason
            self.projectedBytes = projectedBytes
            self.message = message
            self.budgetBytes = budgetBytes
            self.usedBytes = usedBytes
            self.downloadingBytes = downloadingBytes
            self.neededBytes = neededBytes
            self.freeDiskBytes = freeDiskBytes
        }
    }

    public enum Check: Sendable, Equatable {
        case ok(projectedBytes: Int64)
        case refused(Refused)

        public var projectedBytes: Int64 {
            switch self {
            case .ok(let p): return p
            case .refused(let r): return r.projectedBytes
            }
        }

        public var isOk: Bool { if case .ok = self { return true } else { return false } }
    }

    public static func check(_ input: Input) -> Check {
        let projected = appReserveBytes + input.usedBytes + input.reservedBytes + input.downloadBytes
        if projected > input.budgetBytes {
            return .refused(Refused(
                reason: .budget, projectedBytes: projected,
                message: "Not enough room in BOAR's \(Units.formatBytes(input.budgetBytes)) storage budget: this \(Units.formatBytes(input.downloadBytes)) download " +
                    "would bring the total to about \(Units.formatBytes(projected)). Remove a model first.",
                budgetBytes: input.budgetBytes, usedBytes: input.usedBytes, downloadingBytes: input.reservedBytes,
                neededBytes: input.downloadBytes, freeDiskBytes: input.freeDiskBytes))
        }
        let stillNeeded = max(input.downloadBytes - input.alreadyDownloadedBytes, 0)
        if let free = input.freeDiskBytes, stillNeeded + freeSpaceMarginBytes > free {
            return .refused(Refused(
                reason: .disk, projectedBytes: projected,
                message: "Not enough free space on this phone: the download needs \(Units.formatBytes(stillNeeded)) and only " +
                    "\(Units.formatBytes(free)) is free. Free up space or remove a model first.",
                budgetBytes: input.budgetBytes, usedBytes: input.usedBytes, downloadingBytes: input.reservedBytes,
                neededBytes: stillNeeded, freeDiskBytes: free))
        }
        return .ok(projectedBytes: projected)
    }
}
