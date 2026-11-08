import BoarCore
import SwiftUI

/// One benchmark answer: the question, its topic, model and time, and what the fact check found; a tap shows why, the
/// measurements and the answer.
struct EvalResultRow: View {
    let row: JSONValue
    let modelName: String
    @Binding var expanded: String?

    private var key: String { "\(row["configId"]?.stringValue ?? "")/\(row["queryId"]?.stringValue ?? "")" }
    private var open: Bool { expanded == key }
    private var outcome: String { row["outcome"]?.stringValue ?? "" }
    private var check: String? { row["check"]?.stringValue }
    private var why: String { row["checkWhy"]?.stringValue ?? "" }

    private var status: (name: String, color: BoarStyle, label: LocalizedStringKey) {
        if outcome == "cancelled" { return (Symbols.caution, .boar(.warning), "Stopped") }
        if outcome == "failure" { return (Symbols.error, .boar(.danger), "Failed") }
        switch check {
        case "pass": return (Symbols.fits, .boar(.success), "Facts found")
        case "refused": return why == "ok" ? (Symbols.fits, .boar(.success), "Declined, which is allowed here") : ("hand.raised", .boar(.secondary), "Declined")
        case "confident-wrong": return ("xmark.octagon", .boar(.danger), "Wrong claim")
        case "fail-missing": return ("minus.circle", .boar(.warning), "Facts missing")
        case "empty": return (Symbols.error, .boar(.danger), "No answer")
        default: return ("desktopcomputer", .boar(.secondary), "Judged on a computer")
        }
    }

    private var summary: String {
        [EvalFormat.category(row["category"]?.stringValue ?? ""), modelName, FeatureFormat.milliseconds(row["totalLatencyMs"]?.doubleValue)]
            .joined(separator: " · ")
    }

    /// What the check found, in words.
    private var finding: LocalizedStringKey? {
        switch check {
        case "confident-wrong": "Wrong claim: \(why)"
        case "fail-missing": "Missing: \(why)"
        case "refused": why == "ok" ? "Declined; declining is a fair answer to this question." : "Declined a question it should answer."
        default: nil
        }
    }

    private var facts: String {
        let titles = row["retrievedTitles"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let rate = row["tokPerSec"]?.doubleValue.map { EvalFormat.tokensPerSecond($0) }
        let sources = row["retrievalUsed"]?.boolValue == true ? titles.prefix(3).joined(separator: ", ") : String(localized: "no retrieval")
        let hit: String? = switch row["sourceHit"]?.boolValue {
        case true?: String(localized: "reference source found")
        case false?: String(localized: "reference source not found")
        case nil: nil
        }
        return [
            [row["queryId"]?.stringValue, row["modelId"]?.stringValue].compactMap { $0 }.joined(separator: " · "),
            [String(localized: "load \(FeatureFormat.milliseconds(row["modelLoadMs"]?.doubleValue))"),
             String(localized: "first word \(FeatureFormat.milliseconds(row["ttftMs"]?.doubleValue))"), rate].compactMap { $0 }.joined(separator: " · "),
            [sources, hit].compactMap { $0 }.joined(separator: " · "),
        ].joined(separator: "\n")
    }

    private var answer: String {
        outcome == "failure" ? (row["errorMessage"]?.stringValue ?? "") : (row["answer"]?.stringValue ?? "")
    }

    var body: some View {
        let status = status
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(verbatim: row["query"]?.stringValue ?? row["queryId"]?.stringValue ?? "")
                            .lineLimit(open ? nil : 2)
                        Text(verbatim: summary)
                            .boarText("mono.xs")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: status.name)
                        .foregroundStyle(status.color)
                        .accessibilityLabel(status.label)
                }
                if open {
                    if let finding {
                        Text(finding)
                            .font(.boar("ui.subtext"))
                            .foregroundStyle(status.color)
                    }
                    Text(verbatim: facts)
                        .boarText("mono.xs")
                        .foregroundStyle(.secondary)
                    Text(verbatim: answer)
                        .font(.boar("ui.subtext"))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(open ? "Hides the details" : "Shows the details and the answer")
    }

    private func toggle() {
        withAnimation(.snappy) { expanded = open ? nil : key }
    }
}
