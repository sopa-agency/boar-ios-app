import BoarAnswer
import SwiftUI

/// Levels and topics (android PresetSection; adam, Nov 14: "fast, only succinct mode. medium, complete. and by topics"):
/// what the chosen preset runs and how long it should take before it starts ("this waiting sucks"). By hand keeps the
/// question sets and the ticked models below.
struct EvalPresetSection: View {
    let controller: EvaluationController
    @Environment(\.locale) private var locale

    private var levelBinding: Binding<String> {
        Binding(get: { controller.level?.id ?? "" }, set: { controller.setLevel(BenchLevel.of($0)) })
    }

    private var topicBinding: Binding<String> {
        Binding(get: { controller.topic }, set: { controller.setTopic($0) })
    }

    var body: some View {
        let pt = locale.language.languageCode?.identifier == "pt"
        Section {
            Picker("Preset", selection: levelBinding) {
                Text("By hand").tag("")
                ForEach(BenchLevel.allCases, id: \.id) { level in
                    Text(level.title).tag(level.id)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controller.running)
            if !controller.byHand && !controller.topics.isEmpty {
                Picker("Topic", selection: topicBinding) {
                    ForEach(controller.topics, id: \.id) { topic in
                        Text(verbatim: topic.title(pt: pt)).tag(topic.id)
                    }
                }
                .disabled(controller.running)
                if let plan = controller.plan {
                    LabeledContent("Models") {
                        Text(verbatim: plan.models.map(\.label).joined(separator: ", "))
                    }
                    if let e = controller.estimate {
                        Text(Self.expected(e, plan: plan))
                            .boarText("mono.xs")
                            .fontWeight(.semibold)
                            .foregroundStyle(.boar(.link))
                    }
                } else if let error = controller.planError {
                    Text(verbatim: error)
                        .font(.boar("ui.subtext"))
                        .foregroundStyle(.boar(.danger))
                }
            }
        } header: {
            BoarHeader {
                Text("Preset")
            }
        } footer: {
            BoarFooter {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.level?.note ?? "The models you tick, in the default style.")
                    if !controller.byHand, let topic = controller.topics.first(where: { $0.id == controller.topic }) {
                        if !topic.about.isEmpty { Text(verbatim: topic.about) }
                        if topic.status.hasPrefix("draft") { Text("Draft: its rules don't count yet.") }
                    }
                }
            }
        }
    }

    /// "Expected: about 2 min for 17 answers (from the F3's medians)".
    static func expected(_ e: BenchPresets.Estimate, plan: BenchPlan) -> String {
        let time = duration(e.seconds)
        var line = String(localized: "Expected: about \(time) for \(plan.answers) answers")
        if e.untimed > 0 { line += ", " + String(localized: "plus \(e.untimed) Deep Research answers nobody has timed yet") }
        let level = String(localized: plan.preset.level.title)
        let source = e.fromPrevious ? String(localized: "from the last \(level) run on this device") : String(localized: "from the F3's medians")
        return line + " (" + source + ")"
    }

    /// Android's duration: seconds, then rounded minutes, then hours and minutes.
    static func duration(_ seconds: Double) -> String {
        let s = Int64(seconds)
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\((s + 30) / 60) min" }
        return "\(s / 3600) h \((s % 3600 + 30) / 60) min"
    }
}

extension BenchLevel {
    var title: LocalizedStringResource {
        switch self {
        case .fast: "Fast"
        case .medium: "Medium"
        case .complete: "Complete"
        }
    }

    var note: LocalizedStringKey {
        switch self {
        case .fast: "Succinct, on the 1.7B (or the only answer model)."
        case .medium: "Succinct, on the 1.7B and the 4B."
        case .complete: "Succinct and Detailed on both models, and Deep Research for the research topic."
        }
    }
}
