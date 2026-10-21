import Foundation
import os

/// Device facts the engine's rules need.
public enum DeviceInfo {
    /// Physical RAM in bytes (sizes the Auto context, the load guard and the storage budget).
    public static var totalRamBytes: Int64 { Int64(clamping: ProcessInfo.processInfo.physicalMemory) }
}

/// One logger per module: `team.sopa.boar` / category. Engine code logs through this; no `print`.
public enum BoarLog {
    public static let subsystem = "team.sopa.boar"
    public static func logger(_ category: String) -> Logger { Logger(subsystem: subsystem, category: category) }
}
