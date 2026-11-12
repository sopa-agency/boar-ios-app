import Darwin
import Foundation
import Network
import Observation

/// The memory BOAR holds right now (android `AppMemory.residentBytes`): the physical footprint iOS charges to the app,
/// which is what the jetsam limit is measured against (model pages mapped from the file included once touched).
enum AppMemory {
    static func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

/// ONLINE / OFFLINE for the header badge (connectivity.pure.ts isOnline: a satisfied path, not just an interface).
@MainActor
@Observable
final class Connectivity {
    /// `NWPath.Status`, kept Sendable.
    enum Status: Sendable { case satisfied, unsatisfied, requiresConnection }

    /// The last path's status; nil until the monitor's first report.
    private(set) var status: Status?
    var online: Bool { status == .satisfied }
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var waiting: [CheckedContinuation<Status?, Never>] = []

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status: Status = switch path.status {
            case .satisfied: .satisfied
            case .requiresConnection: .requiresConnection
            default: .unsatisfied
            }
            Task { @MainActor in self?.update(status) }
        }
        monitor.start(queue: DispatchQueue(label: "team.sopa.boar.connectivity"))
    }

    deinit { monitor.cancel() }

    /// The status once the monitor has reported (at launch it takes a moment); nil if it hasn't within `timeout`.
    func settledStatus(timeout: Duration = .seconds(2)) async -> Status? {
        if let status { return status }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { self?.release(nil) }
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func update(_ status: Status) {
        self.status = status
        release(status)
    }

    private func release(_ status: Status?) {
        let all = waiting
        waiting = []
        for c in all { c.resume(returning: status) }
    }
}

/// Free space and RAM of this iPhone, as iOS Settings reports them.
enum DeviceStorage {
    /// Space available for important downloads on the app's volume (what iOS frees up for the app if needed).
    static func availableBytes() -> Int64? {
        let url = URL.homeDirectory
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static var physicalMemoryBytes: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }
}
