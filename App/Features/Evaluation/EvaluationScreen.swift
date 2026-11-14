import BoarAnswer
import BoarCore
import SwiftUI

/// Runs a question set from the public research bench (or the app's original set) against the chosen models and shows
/// the offline checks per model and per topic (docs/BENCHMARK-SCREEN.md). Results save as they come and leave the phone
/// only through the share sheet.
struct EvaluationScreen: View {
    let controller: EvaluationController
    let chatBusy: Bool
    @State private var expanded: String?

    var body: some View {
        let summary = controller.summary
        GroupedList {
            EvalSetSection(controller: controller)
            EvalConfigsSection(controller: controller)
            EvalRunSection(controller: controller, chatBusy: chatBusy)
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
            if !summary.configs.isEmpty {
                EvalComparisonSection(controller: controller, summary: summary)
                EvalCategorySection(controller: controller, summary: summary)
                Section("Answers") {
                    ForEach(Array(controller.rows.enumerated()), id: \.offset) { _, row in
                        EvalResultRow(row: row, modelName: controller.name(configId: row["configId"]?.stringValue ?? "",
                                                                           label: row["configLabel"]?.stringValue ?? "").plain,
                                      expanded: $expanded)
                    }
                }
            }
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
        .onAppear {
            controller.load()
            controller.startPolling()
            #if DEBUG
            if DebugLaunch.demo && DebugLaunch.isScreen("evaluation") { controller.debugShowDemo() }
            #endif
        }
        .onDisappear {
            #if !DEBUG
            controller.stopPolling()
            #endif
        }
    }
}
