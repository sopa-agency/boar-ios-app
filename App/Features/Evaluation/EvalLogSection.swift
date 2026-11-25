import BoarAnswer
import BoarModels
import SwiftUI

/// The run's log on top while it runs (android BenchActivity's Log; adam, Nov 12): newest line first, a line when each
/// question starts, and a clock since the last line so a long answer doesn't look stuck.
struct EvalLogSection: View {
    let controller: EvaluationController

    var body: some View {
        Section {
            let lines = BenchLog.newestFirst(controller.log)
            if lines.isEmpty {
                Text("Starting…")
                    .boarText("mono.xs")
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: lines.joined(separator: "\n"))
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.primary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            BoarHeader {
                HStack {
                    Text("Log")
                    Spacer()
                    if let at = controller.lastLineAt {
                        TimelineView(.periodic(from: at, by: 1)) { context in
                            Text(Self.since(context.date.timeIntervalSince(at)))
                                .boarText("mono.xs")
                                .fontWeight(.bold)
                                .foregroundStyle(.boar(.accent))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    /// "● last line 42 s ago", "● last line 2 min 5 s ago".
    static func since(_ interval: TimeInterval) -> LocalizedStringKey {
        let (minutes, seconds) = BenchLog.since(ms: Int64(interval * 1000))
        if let minutes { return "● last line \(minutes) min \(seconds) s ago" }
        return "● last line \(seconds) s ago"
    }
}

/// The device's vitals, compact, above the log (android BenchVitals; adam, Nov 14: "display vitals dashboard during
/// engine bench? a compact version. above logs"): heat as the system reports it, with its peak during the run; battery;
/// BOAR's own memory and what it can still use. Read every second, as the Vitals plugin does, with no plugin needed.
/// iOS gives no temperature or per-core clocks, so the thermal state stands for both.
struct EvalVitalsSection: View {
    @State private var now: PluginAnswers.PhoneNow?
    @State private var peakHeat = 0
    @State private var boarBytes: Int64 = 0

    var body: some View {
        Section {
            if let s = now {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(Self.heatWord(s.heatLevel))
                            .font(.boar("ui.subtext").weight(.heavy))
                            .foregroundStyle(Self.heatColor(s.heatLevel))
                        if peakHeat > (s.heatLevel ?? 0) {
                            Text("peak: \(Text(Self.heatWord(peakHeat)))")
                                .boarText("mono.xs")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: (s.batteryPct.map { "\($0)%" } ?? "—") + (s.charging == true ? " ⚡" : ""))
                            .boarText("mono.xs")
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                    // Two lines, each whole (adam, Nov 14: "use 2 lines for cpu and ram").
                    Text("CPU \(s.cores ?? 0) cores · BOAR \(Self.gb(boarBytes)) GB")
                        .boarText("mono.xs")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let free = s.ramFreeMb, let total = s.ramTotalMb {
                        Text("RAM \(Self.gb(free * 1_048_576)) GB free for BOAR of \(Self.gb(total * 1_048_576)) GB")
                            .boarText("mono.xs")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let total = s.ramTotalMb {
                        Text("RAM \(Self.gb(total * 1_048_576)) GB")
                            .boarText("mono.xs")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            BoarHeader {
                Text("Vitals")
            }
        }
        .task {
            while !Task.isCancelled {
                let s = PhoneReads.readPhone()
                now = s
                peakHeat = max(peakHeat, s.heatLevel ?? 0)
                boarBytes = AppMemory.footprintBytes()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    static func gb(_ bytes: Int64) -> String { String(format: "%.1f", Double(bytes) / 1_073_741_824) }

    /// ProcessInfo.thermalState as PhoneReads gives it: 0 nominal, 1 fair, 2 serious, 3 critical.
    static func heatWord(_ level: Int?) -> LocalizedStringKey {
        switch level {
        case 0?: "Normal heat"
        case 1?: "Warm"
        case 2?: "Hot · slowing down"
        case 3?: "Too hot · slowing down hard"
        default: "Heat unknown"
        }
    }

    static func heatColor(_ level: Int?) -> BoarStyle {
        switch level {
        case 0?: .boar(.success)
        case 1?: .boar(.warning)
        case 2?, 3?: .boar(.danger)
        default: .boar(.muted)
        }
    }
}
