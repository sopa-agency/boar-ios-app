import Foundation
#if canImport(os)
import os
#endif

/// Memory facts for the RAM-fit rules, from the iOS APIs (Android: `ActivityManager`/`/proc/meminfo`).
public enum DeviceMemory {
    /// Physical RAM in bytes (what `Compatibility` and `SetupModel` take as the device RAM).
    public static var totalBytes: Int64 { Int64(clamping: ProcessInfo.processInfo.physicalMemory) }

    /// Bytes this process can still allocate before the system kills it (`os_proc_available_memory`, iOS only).
    /// nil where the API doesn't exist (macOS host tests).
    public static var availableBytes: Int64? {
        #if os(iOS) || os(visionOS) || os(tvOS)
        let n = os_proc_available_memory()
        return n > 0 ? Int64(clamping: n) : nil
        #else
        return nil
        #endif
    }
}

/// Free space on the volume that holds the models, for `StorageBudget`.
public enum DiskSpace {
    /// `volumeAvailableCapacityForImportantUsage` of the volume holding `url` (the nearest existing ancestor when `url`
    /// doesn't exist yet). nil when unknown or not positive (the Kotlin `usableSpace.takeIf { it > 0 }`).
    public static func freeBytes(at url: URL) -> Int64? {
        var probe = url
        let fm = FileManager.default
        while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe = probe.deletingLastPathComponent() }
        guard let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) else { return nil }
        // Headless sessions (SSH, no GUI login) report 0 for important usage; fall back to the plain free space.
        if let free = values.volumeAvailableCapacityForImportantUsage, free > 0 { return free }
        if let free = values.volumeAvailableCapacity, free > 0 { return Int64(free) }
        return nil
    }
}
