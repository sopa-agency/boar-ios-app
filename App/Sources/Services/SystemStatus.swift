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
    private(set) var online = false
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.online = online }
        }
        monitor.start(queue: DispatchQueue(label: "team.sopa.boar.connectivity"))
    }

    deinit { monitor.cancel() }
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
