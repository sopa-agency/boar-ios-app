import BoarAnswer
import SwiftUI

/// The run's numbers side by side, one column per model.
struct EvalComparisonSection: View {
    let controller: EvaluationController
    let summary: EvalSummary

    private struct Metric: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let value: (EvalSummary.Stats) -> String
    }

    private var metrics: [Metric] {
        var m = [
            Metric(id: "facts", title: "Facts checked") { EvalFormat.fraction($0.passed, $0.checked) },
            Metric(id: "wrong", title: "Wrong claims") { $0.checked > 0 ? "\($0.wrong)" : "—" },
            Metric(id: "source", title: "Source found") { EvalFormat.fraction($0.sourceHits, $0.sourceItems) },
            Metric(id: "p50", title: "Time per answer") { FeatureFormat.milliseconds($0.totalP50Ms) },
            Metric(id: "p90", title: "Slowest 10 %") { FeatureFormat.milliseconds($0.totalP90Ms) },
            Metric(id: "ttft", title: "First word") { FeatureFormat.milliseconds($0.ttftP50Ms) },
            Metric(id: "speed", title: "Writing speed") { EvalFormat.tokensPerSecond($0.tokPerSecMedian) },
            Metric(id: "load", title: "Model load") { FeatureFormat.milliseconds($0.loadMs) },
            Metric(id: "memory", title: "Peak memory") { EvalFormat.bytes($0.peakBytes) },
        ]
        if summary.configs.contains(where: { $0.overall.failed + $0.overall.cancelled > 0 }) {
            m.append(Metric(id: "failed", title: "Failed or stopped") { "\($0.failed + $0.cancelled)" })
        }
        return m
    }

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(summary.configs) { config in
                        Text(verbatim: controller.name(configId: config.configId, label: config.label).plain)
                            .font(.subheadline.weight(.semibold))
                            .gridColumnAlignment(.trailing)
                    }
                }
                ForEach(metrics) { metric in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(metric.title)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(summary.configs) { config in
                            Text(verbatim: metric.value(config.overall))
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(summary.configs.count > 1 ? "Comparison" : "Summary")
        } footer: {
            Text("Facts checked looks for each question's expected facts and known wrong claims by keyword. It agrees with hand grading about 88% of the time and is not the bounty score: share the traces for the judge and score them on a computer.")
        }
    }
}
