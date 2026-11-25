import BoarAnswer
import SwiftUI

/// The scorecard (android ScorecardSection, t9 0521 item 4): one line per topic, passed over checked, against the previous
/// run of the same preset; one line per model and pass with its first word, whole answer and peak memory.
struct EvalScorecardSection: View {
    let card: Scorecard.Card

    var body: some View {
        Section {
            ForEach(card.topics, id: \.topic) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: line.topic)
                            .font(.boar("ui.subtext").weight(.semibold))
                        Spacer()
                        Text("\(line.passed)/\(line.checked) passed")
                            .boarText("mono.xs")
                            .monospacedDigit()
                        if let trend = line.trend {
                            Text(trend.label)
                                .boarText("mono.xs")
                                .fontWeight(.semibold)
                                .foregroundStyle(trend.color)
                        }
                    }
                    Text(verbatim: Self.details(line))
                        .boarText("mono.xs")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(card.models.enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(m.modelId) · \(m.pass)")
                        .font(.boar("ui.subtext").weight(.semibold))
                        .lineLimit(1)
                    Text("first word \(FeatureFormat.milliseconds(m.firstWordMs)) · whole answer \(FeatureFormat.milliseconds(m.wholeAnswerMs)) · peak \(Self.peak(m.peakRssBytes))")
                        .boarText("mono.xs")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            BoarHeader {
                Text("Scorecard")
            }
        } footer: {
            BoarFooter {
                Text("The computer scores only what a rule can check (a plugin's exact text, the language, cards, sources, numbers). The rest is to read.")
            }
        }
    }

    /// "was 1/3 · 2 to read", with the known issues and skipped questions when there are some.
    static func details(_ line: Scorecard.TopicLine) -> String {
        var parts: [String] = []
        if let checked = line.previousChecked { parts.append(String(localized: "was \(line.previousPassed ?? 0)/\(checked)")) }
        parts.append(String(localized: "\(line.toRead) to read"))
        if line.known > 0 { parts.append(String(localized: "\(line.known) known issues")) }
        if line.skipped > 0 { parts.append(String(localized: "\(line.skipped) skipped (plugin off)")) }
        return parts.joined(separator: " · ")
    }

    static func peak(_ bytes: Double?) -> String { bytes.map { String(format: "%.2f GB", $0 / 1e9) } ?? "—" }
}

extension Scorecard.Trend {
    var label: LocalizedStringKey {
        switch self {
        case .up: "↑ up"
        case .down: "↓ down"
        case .same: "= same"
        }
    }

    var color: BoarStyle {
        switch self {
        case .up: .boar(.success)
        case .down: .boar(.danger)
        case .same: .boar(.muted)
        }
    }
}

extension Scorecard.Verdict {
    var label: LocalizedStringKey {
        switch self {
        case .pass: "Passed"
        case .fail: "Failed"
        case .known: "Known issue"
        case .skipped: "Skipped"
        case .toRead: "To read"
        }
    }

    var color: BoarStyle {
        switch self {
        case .pass: .boar(.success)
        case .fail: .boar(.danger)
        case .known: .boar(.warning)
        case .skipped, .toRead: .boar(.muted)
        }
    }
}
