import BoarAnswer
import SwiftUI

/// Facts checked per topic, one column per model.
struct EvalCategorySection: View {
    let controller: EvaluationController
    let summary: EvalSummary

    /// Every category in the order it first appears across the models.
    private var categories: [String] {
        var seen: [String] = []
        for config in summary.configs {
            for c in config.categories where !seen.contains(c.category) { seen.append(c.category) }
        }
        return seen
    }

    /// "2/3", "—" when the model has no answer in it, nil when the phone can't grade it.
    private func cell(_ config: EvalSummary.Config, _ category: String) -> String? {
        guard let s = config.categories.first(where: { $0.category == category })?.stats else { return "—" }
        return s.checked > 0 ? EvalFormat.fraction(s.passed, s.checked) : nil
    }

    var body: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if summary.configs.count > 1 {
                    GridRow {
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(summary.configs) { config in
                            Text(verbatim: controller.name(configId: config.configId, label: config.label).plain)
                                .font(.subheadline.weight(.semibold))
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                ForEach(categories, id: \.self) { category in
                    if summary.configs.count > 1 || category != categories.first {
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                    }
                    GridRow {
                        Text(verbatim: EvalFormat.category(category))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(summary.configs) { config in
                            let value = cell(config, category)
                            Text(verbatim: value ?? String(localized: "computer"))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(value == nil ? .secondary : .primary)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("By Topic")
        } footer: {
            BoarFooter {
                Text("Facts checked per topic. “computer” marks topics the phone can't grade: venue lists, first aid and open-ended answers go to the judge.")
            }
        }
    }
}
