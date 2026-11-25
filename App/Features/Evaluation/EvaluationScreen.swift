import BoarAnswer
import BoarCore
import SwiftUI

/// Runs a question set from the public research bench (or the app's original set) against the chosen models and shows
/// the offline checks per model and per topic (docs/BENCHMARK-SCREEN.md). Since v2.0.0 also presets by level and topic,
/// their scorecard, and every saved run. Results save as they come and leave the phone only through the share sheet.
struct EvaluationScreen: View {
    let controller: EvaluationController
    let chatBusy: Bool
    @State private var expanded: String?
    @State private var confirmDelete: String?

    var body: some View {
        let summary = controller.summary
        GroupedList {
            // While it runs, the device's vitals and the log come first (android BenchActivity: the log on top).
            if controller.running {
                EvalVitalsSection()
                EvalLogSection(controller: controller)
            }
            if let run = controller.opened {
                EvalOpenedSection(controller: controller, run: run, confirmDelete: $confirmDelete)
            } else {
                EvalPresetSection(controller: controller)
                if controller.byHand {
                    EvalSetSection(controller: controller)
                    EvalConfigsSection(controller: controller)
                }
                EvalRunSection(controller: controller, chatBusy: chatBusy)
            }
            if let p = controller.progress {
                Section("Progress") {
                    ProgressView(value: Double(p.configIndex * p.queryCount + p.queryIndex), total: Double(max(p.configCount * p.queryCount, 1))) {
                        Text("Model \(p.configIndex + 1) of \(p.configCount) · Question \(p.queryIndex + 1) of \(p.queryCount)")
                            .monospacedDigit()
                    } currentValueLabel: {
                        Text(verbatim: controller.name(p.config).full)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if controller.running || !controller.rows.isEmpty {
                EvalScoreSection(controller: controller)
            }
            if let card = controller.scorecard, !controller.running, !card.topics.isEmpty {
                EvalScorecardSection(card: card)
            }
            if !summary.configs.isEmpty {
                EvalComparisonSection(controller: controller, summary: summary)
                EvalCategorySection(controller: controller, summary: summary)
                Section("Answers") {
                    let verdicts = controller.scorecard?.rows ?? []
                    ForEach(Array(controller.rows.enumerated()), id: \.offset) { i, row in
                        EvalResultRow(row: row, modelName: controller.name(configId: row["configId"]?.stringValue ?? "",
                                                                           label: row["configLabel"]?.stringValue ?? "").plain,
                                      index: i,
                                      verdict: i < verdicts.count && verdicts[i].queryId == row["queryId"]?.stringValue ? verdicts[i] : nil,
                                      expanded: $expanded)
                    }
                }
            }
            EvalSavedSection(controller: controller, confirmDelete: $confirmDelete)
        }
        .readableWidth(760)
        .navigationTitle("Benchmark")
        .inlineNavigationTitle()
        .toolbar {
            if controller.runId != nil && !controller.running {
                ToolbarItem(placement: .primaryAction) {
                    EvalShareMenu(controller: controller, configs: summary.configs)
                }
            }
        }
        .confirmationDialog("Delete this run?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { id in
            Button("Delete", role: .destructive) {
                controller.delete(id)
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: { _ in
            Text("Its answers are deleted from this \(Platform.deviceNoun) and can't be brought back. Exports you made are kept.")
        }
        .onAppear {
            controller.load()
            // Runs started from a connected computer since the page was last open show up too.
            controller.refreshSaved()
            controller.startPolling()
            #if DEBUG
            if DebugLaunch.demo && DebugLaunch.isScreen("evaluation") { controller.debugShowDemo() }
            if DebugLaunch.demo && DebugLaunch.isScreen("evaluation-preset") { controller.debugShowPresetDemo() }
            #endif
        }
        .onDisappear {
            #if !DEBUG
            controller.stopPolling()
            #endif
        }
    }
}
