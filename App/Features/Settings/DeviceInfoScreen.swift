import BoarCore
import BoarModels
import SwiftUI

/// Settings → Advanced → iPhone & Storage (android TelemetrySection / UsageStatsContent): this iPhone, what BOAR uses
/// now, and the benchmarks it ran. Read only; nothing here leaves the phone.
struct DeviceInfoScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var storage: Int64?
    @State private var free: Int64?
    @State private var footprint: Int64 = 0
    /// What BOAR can still allocate before iOS ends it (nil on the Mac).
    @State private var available: Int64?
    @State private var evals: (count: Int, last: Date?) = (0, nil)

    var body: some View {
        let topology = services.topology
        let fastest = topology.cores.map(\.maxKhz).max()
        let performance = topology.cores.filter { $0.maxKhz == fastest }.count
        BoarForm {
            Section {
                if let name = DeviceName.current {
                    ValueRow(label: "Model", value: name)
                }
                ValueRow(label: "\(Platform.systemName) Version", value: Platform.systemVersion)
                ValueRow(label: "Memory", value: DeviceStorage.physicalMemoryBytes.formatted(.byteCount(style: .memory)))
                if !topology.cores.isEmpty {
                    ValueRow(label: "Processor Cores", value: String(localized: "\(topology.cores.count) (\(performance) performance)"))
                }
                if let free {
                    ValueRow(label: "Free Storage", value: free.formatted(.byteCount(style: .file)))
                }
            } header: {
                BoarHeader {
                    Text(verbatim: Platform.deviceNoun)
                }
            }

            Section {
                // Memory against what iOS lets BOAR use before it ends the app (android shows BOAR and the other apps
                // against the phone's RAM; iOS doesn't tell an app what the others use). The Mac has no such limit.
                if footprint > 0 {
                    if let available {
                        UsageBar(title: "Memory", used: footprint, total: footprint + available,
                                 caption: String(localized: "BOAR \(footprint.formatted(.byteCount(style: .memory))) · \(available.formatted(.byteCount(style: .memory))) more before \(Platform.systemName) closes it"))
                    } else {
                        UsageBar(title: "Memory", used: footprint, total: DeviceStorage.physicalMemoryBytes,
                                 caption: String(localized: "BOAR \(footprint.formatted(.byteCount(style: .memory))) of this \(Platform.deviceNoun)'s memory"))
                    }
                }
                if let storage {
                    // Boar Labs can set another limit, or none: then the bar runs to what the device still has free.
                    let limit = StorageBudget.limit(catalogBudget: services.catalog.storageBudgetBytes)
                    if limit == StorageBudget.noLimit {
                        UsageBar(title: "Storage", used: storage, total: storage + (free ?? 0),
                                 caption: String(localized: "No BOAR limit: up to the \(Platform.deviceNoun)'s free space"), kind: .storage)
                    } else {
                        UsageBar(title: "Storage", used: storage, total: limit,
                                 caption: String(localized: "BOAR's storage limit, not the \(Platform.deviceNoun)'s"), kind: .storage)
                    }
                }
                ValueRow(label: "Saved Chats", value: model.sessions.count.formatted())
                ValueRow(label: "Benchmark Runs", value: evals.count.formatted())
                if let last = evals.last {
                    ValueRow(label: "Last Benchmark", value: last.formatted(date: .abbreviated, time: .omitted))
                }
            } header: {
                BoarHeader {
                    Text("BOAR")
                }
            } footer: {
                BoarFooter {
                    Text("Nothing here leaves your \(Platform.deviceNoun).")
                }
            }
        }
        .navigationTitle("\(Platform.deviceNoun) & Storage")
        .inlineNavigationTitle()
        .task {
            free = (try? await services.background { _ in DeviceStorage.availableBytes() }) ?? nil
            if let runner = model.evaluation?.runner {
                evals = await Task.detached { Self.lastEval(runner) }.value
            }
            // Read every 5 s while the screen is open, like Android's.
            while !Task.isCancelled {
                footprint = AppMemory.footprintBytes()
                available = DeviceMemory.availableBytes
                storage = try? await services.background { $0.storageUsedBytes() }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    nonisolated private static func lastEval(_ runner: EvalRunner) -> (Int, Date?) {
        let runs = runner.savedRuns()
        return (runs.count, runs.last.map(EvalRunner.modified))
    }
}
