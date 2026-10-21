import BoarCore
import SwiftUI

/// Settings → Advanced → iPhone & Storage (android TelemetrySection / UsageStatsContent): this iPhone, what BOAR uses
/// now, and the benchmarks it ran. Read only; nothing here leaves the phone.
struct DeviceInfoScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var storage: Int64?
    @State private var free: Int64?
    @State private var footprint: Int64 = 0
    @State private var evals: (count: Int, last: Date?) = (0, nil)

    var body: some View {
        let topology = services.topology
        let fastest = topology.cores.map(\.maxKhz).max()
        let performance = topology.cores.filter { $0.maxKhz == fastest }.count
        Form {
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
                Text(verbatim: Platform.deviceNoun)
            }

            Section {
                if footprint > 0 {
                    ValueRow(label: "Memory in Use", value: footprint.formatted(.byteCount(style: .file)))
                }
                if let storage {
                    ValueRow(label: "Storage Used", value: storage.formatted(.byteCount(style: .file)))
                }
                ValueRow(label: "Saved Chats", value: model.sessions.count.formatted())
                ValueRow(label: "Benchmark Runs", value: evals.count.formatted())
                if let last = evals.last {
                    ValueRow(label: "Last Benchmark", value: last.formatted(date: .abbreviated, time: .omitted))
                }
            } header: {
                Text("BOAR")
            } footer: {
                Text("Nothing here leaves your \(Platform.deviceNoun).")
            }
        }
        .navigationTitle("\(Platform.deviceNoun) & Storage")
        .inlineNavigationTitle()
        .task {
            footprint = AppMemory.footprintBytes()
            free = (try? await services.background { _ in DeviceStorage.availableBytes() }) ?? nil
            storage = try? await services.background { $0.storageUsedBytes() }
            if let runner = model.evaluation?.runner {
                evals = await Task.detached { Self.lastEval(runner) }.value
            }
        }
    }

    nonisolated private static func lastEval(_ runner: EvalRunner) -> (Int, Date?) {
        let runs = runner.savedRuns()
        return (runs.count, runs.last.map(EvalRunner.modified))
    }
}
