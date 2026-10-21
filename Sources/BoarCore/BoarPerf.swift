import Foundation
import os

/// Performance marks for Instruments and the device log. Intervals show in the Points of Interest lane (Time Profiler,
/// System Trace, `scripts/perf.sh`); every mark also logs the process memory under `team.sopa.boar` / `perf`, so a
/// device log (`scripts/perf.sh log`) shows what a step cost without Instruments.
public enum BoarPerf {
    public static let signposter = OSSignposter(subsystem: BoarLog.subsystem, category: .pointsOfInterest)
    static let log = BoarLog.logger("perf")

    /// The process's memory now, in MB: `footprint` is what jetsam counts (phys_footprint), `available` the headroom
    /// before this app is killed (`os_proc_available_memory`, iOS only; nil elsewhere).
    public struct Memory: Sendable, CustomStringConvertible {
        public let footprintMB: Int
        public let availableMB: Int?
        public var description: String { "footprint \(footprintMB) MB, headroom \(availableMB.map { "\($0) MB" } ?? "n/a")" }
    }

    public static func memory() -> Memory {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let footprint = kr == KERN_SUCCESS ? Int(info.phys_footprint >> 20) : 0
        #if os(iOS) || os(visionOS) || os(tvOS)
        let available: Int? = Int(os_proc_available_memory() >> 20)
        #else
        let available: Int? = nil
        #endif
        return Memory(footprintMB: footprint, availableMB: available)
    }

    /// One timed step: a signpost interval plus a log line with its duration and the memory before and after.
    public struct Interval: Sendable {
        let name: StaticString
        let detail: String
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
        let before: Memory

        public func end(_ outcome: String = "") {
            let d = start.duration(to: .now)
            let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            BoarPerf.signposter.endInterval(name, state, "\(outcome, privacy: .public)")
            let after = BoarPerf.memory()
            BoarPerf.log.notice("\(name, privacy: .public) \(detail, privacy: .public) \(outcome, privacy: .public): \(Int(ms)) ms, footprint \(before.footprintMB)→\(after.footprintMB) MB, headroom \(after.availableMB ?? -1) MB")
        }
    }

    public static func begin(_ name: StaticString, _ detail: String = "") -> Interval {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(detail, privacy: .public)")
        return Interval(name: name, detail: detail, state: state, start: .now, before: memory())
    }

    /// A point in time on the Points of Interest lane (first token, a main-thread stall), logged with the memory.
    public static func event(_ name: StaticString, _ detail: String = "") {
        signposter.emitEvent(name, "\(detail, privacy: .public)")
        log.notice("\(name, privacy: .public) \(detail, privacy: .public) (\(memory().description, privacy: .public))")
    }
}
