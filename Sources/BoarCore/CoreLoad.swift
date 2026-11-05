import Darwin

/// How busy each CPU core is, for Boar Vitals (android labs/plugins/pulse `DevicePulseLab.kt` shows each core's clock from
/// sysfs; iOS doesn't give apps the clock, so the lab shows each core's load instead). Mach's per-core tick counters
/// (`host_processor_info`, PROCESSOR_CPU_LOAD_INFO) only ever grow; the load is the busy share of the ticks between two
/// snapshots.
public enum CoreLoad {
    /// One core's tick counters since boot.
    public struct Ticks: Sendable, Equatable {
        public var user: UInt64
        public var system: UInt64
        public var idle: UInt64
        public var nice: UInt64
        public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user; self.system = system; self.idle = idle; self.nice = nice
        }
    }

    /// The busy share (0...1) of each core between `before` and `after`; nil for a core with no ticks in between, a core
    /// that is in only one snapshot, or counters that went backwards (32-bit wrap).
    public static func load(before: [Ticks], after: [Ticks]) -> [Double?] {
        after.indices.map { i in
            guard i < before.count else { return nil }
            let a = before[i], b = after[i]
            guard b.user >= a.user, b.system >= a.system, b.idle >= a.idle, b.nice >= a.nice else { return nil }
            let busy = (b.user - a.user) + (b.system - a.system) + (b.nice - a.nice)
            let total = busy + (b.idle - a.idle)
            return total == 0 ? nil : Double(busy) / Double(total)
        }
    }

    /// This device's counters, one per core in the kernel's order; empty when Mach doesn't answer.
    public static func read() -> [Ticks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            // The counters are unsigned 32-bit values in an integer_t array.
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[core * states + Int(state)])) }
            return Ticks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM), idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
    }
}
