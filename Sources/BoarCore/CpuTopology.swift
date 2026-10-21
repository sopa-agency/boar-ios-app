import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The device's cores grouped by speed. Android reads top frequencies from sysfs; iOS exposes performance-level groups
/// (`hw.perflevel0` = performance, `hw.perflevel1` = efficiency) and no frequencies, so `maxKhz` here is a relative rank
/// per group unless the OS reports a real `hw.cpufrequency_max`. Only the ordering and grouping carry meaning.
public struct CpuTopology: Sendable, Equatable {
    public struct Core: Sendable, Equatable, Hashable {
        public var id: Int
        public var maxKhz: Int64
        public init(id: Int, maxKhz: Int64) { self.id = id; self.maxKhz = maxKhz }
    }

    public var cores: [Core]
    public init(cores: [Core]) { self.cores = cores }

    /// Cores in the fastest frequency group, plus the second group when the fastest has fewer than 2 cores (prime + big).
    public var bigCores: [Int] {
        guard let top = cores.map(\.maxKhz).max() else { return [] }
        let sorted = Array(Set(cores.map(\.maxKhz))).sorted(by: >)
        let keep: Set<Int64> = (cores.filter { $0.maxKhz == top }.count < 2 && sorted.count > 1) ? Set(sorted.prefix(2)) : [top]
        return cores.filter { keep.contains($0.maxKhz) }.map(\.id)
    }

    /// The cores Auto runs on: the fastest frequency groups, adding the next group until there are 4 cores, but never the
    /// slowest group once there are 2 (the little cores: every thread then waits for the slowest one). One group: all of them.
    public var autoCores: [Int] {
        let byKhz = Dictionary(grouping: cores, by: \.maxKhz)
        let groups = byKhz.keys.sorted(by: >).map { byKhz[$0]! }
        var keep: [Core] = []
        for (i, group) in groups.enumerated() {
            if keep.count >= 4 || (i == groups.count - 1 && keep.count >= 2) { break }
            keep += group
        }
        return keep.map(\.id).sorted()
    }

    /// "4,5,6,7" style list for `EngineParams.cpus`.
    public func cpuList(_ ids: [Int]) -> String { ids.sorted().map(String.init).joined(separator: ",") }

    /// A topology from performance-level counts (efficiency cores numbered first, as sysfs lists the little ones first).
    public static func fromPerfLevels(performance: Int, efficiency: Int) -> CpuTopology {
        var cores: [Core] = []
        for i in 0..<max(efficiency, 0) { cores.append(Core(id: i, maxKhz: 1_000_000)) }
        for i in 0..<max(performance, 0) { cores.append(Core(id: max(efficiency, 0) + i, maxKhz: 2_000_000)) }
        return CpuTopology(cores: cores)
    }

    /// The cores of this device. Without perflevel sysctls (old chips, simulators on Intel) every core is one group.
    public static func read() -> CpuTopology {
        let p = sysctlInt("hw.perflevel0.logicalcpu"), e = sysctlInt("hw.perflevel1.logicalcpu")
        if let p, p > 0 {
            var t = fromPerfLevels(performance: p, efficiency: e ?? 0)
            if let hz = sysctlInt64("hw.cpufrequency_max"), hz > 0 {
                // A reported max applies to the fastest group; the efficiency group keeps its lower rank.
                let khz = hz / 1000
                t.cores = t.cores.map { $0.maxKhz >= 2_000_000 ? Core(id: $0.id, maxKhz: khz) : Core(id: $0.id, maxKhz: min($0.maxKhz, max(khz - 1, 1))) }
            }
            return t
        }
        let n = max(sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount, 1)
        return CpuTopology(cores: (0..<n).map { Core(id: $0, maxKhz: 0) })
    }
}

func sysctlInt(_ name: String) -> Int? {
    sysctlInt64(name).map { Int($0) }
}

func sysctlInt64(_ name: String) -> Int64? {
    #if canImport(Darwin)
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size == 4 || size == 8 else { return nil }
    if size == 4 {
        var v: Int32 = 0
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int64(v)
    }
    var v: Int64 = 0
    guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
    return v
    #else
    return nil
    #endif
}
