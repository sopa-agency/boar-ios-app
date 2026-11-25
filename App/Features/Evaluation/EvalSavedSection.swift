import BoarAnswer
import SwiftUI

/// Every run kept on the device, newest first (android SavedRunRow; adam, Nov 14: "i run, closed, and now, cant
/// review?"): runs from this screen and from a connected computer, old ones too. A tap opens one with its rows and
/// scorecard; Delete asks first.
struct EvalSavedSection: View {
    let controller: EvaluationController
    @Binding var confirmDelete: String?

    var body: some View {
        Section {
            if controller.saved.isEmpty {
                Text("No runs saved yet. Every run stays on this \(Platform.deviceNoun) until you delete it.")
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.saved) { run in
                Button {
                    controller.open(run.runId)
                } label: {
                    EvalSavedRow(run: run, current: run.runId == controller.opened?.runId)
                }
                .buttonStyle(.plain)
                .disabled(controller.running)
                .swipeActions {
                    if run.runId != controller.runner.activeRunId {
                        Button("Delete", role: .destructive) { confirmDelete = run.runId }
                    }
                }
                .contextMenu {
                    if run.runId != controller.runner.activeRunId {
                        Button("Delete", icon: Symbols.delete, role: .destructive) { confirmDelete = run.runId }
                    }
                }
            }
        } header: {
            BoarHeader {
                Text("Saved Runs (\(controller.saved.count))")
            }
        }
    }
}

/// A saved run in the list: date and build, level and topic, how it ended, its models.
struct EvalSavedRow: View {
    let run: RunMeta
    let current: Bool

    private var stateColor: BoarStyle {
        switch run.state {
        case RunMeta.stateDone: .boar(.success)
        case RunMeta.stateFailed, RunMeta.stateInterrupted: .boar(.danger)
        default: .boar(.warning)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(EvalSavedRow.date(run.createdAt), format: .dateTime.day().month().year().hour().minute())
                    .font(.boar("ui.subtext").weight(.bold))
                    .foregroundStyle(current ? .boar(.accent) : .boar(.heading))
                Spacer()
                Text(EvalSavedRow.stateLabel(run.state))
                    .textCase(.uppercase)
                    .boarText("mono.xs")
                    .fontWeight(.semibold)
                    .foregroundStyle(stateColor)
            }
            Text(verbatim: EvalSavedRow.line(run))
                .boarText("mono.xs")
                .foregroundStyle(.secondary)
            if !run.models.isEmpty {
                Text(verbatim: run.models.joined(separator: ", "))
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.muted))
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// "Fast · plugins · 14 answers · BOAR 2.0.0 · from a computer".
    static func line(_ run: RunMeta) -> String {
        let preset = BenchLevel.of(run.level).map { level in
            ([String(localized: level.title)] + run.topics.filter { $0 != BenchPresets.core }).joined(separator: " · ")
        } ?? String(localized: "by hand")
        return [preset, String(localized: "\(run.rows) answers"), run.appVersion.map { "BOAR \($0)" },
                run.source == "request" ? String(localized: "from a computer") : nil].compactMap { $0 }.joined(separator: " · ")
    }

    static func stateLabel(_ state: String) -> LocalizedStringKey {
        switch state {
        case RunMeta.stateRunning: "running"
        case RunMeta.stateDone: "done"
        case RunMeta.stateStopped: "stopped"
        case RunMeta.stateFailed: "failed"
        default: "interrupted"
        }
    }
}

/// On top of an opened saved run: which one it is, Close and Delete.
struct EvalOpenedSection: View {
    let controller: EvaluationController
    let run: RunMeta
    @Binding var confirmDelete: String?

    var body: some View {
        Section {
            Text(verbatim: run.runId)
                .boarText("mono.xs")
                .foregroundStyle(.secondary)
            Button("Close", icon: Symbols.close, action: controller.closeOpened)
            Button("Delete", icon: Symbols.delete, role: .destructive) { confirmDelete = run.runId }
        } header: {
            BoarHeader {
                Text("Saved Run · \(EvalSavedRow.date(run.createdAt), format: .dateTime.day().month().year().hour().minute())")
            }
        }
    }
}
