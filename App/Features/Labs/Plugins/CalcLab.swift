import BoarAnswer
import BoarRAG
import SwiftUI

/// Boar Calculator (android labs/plugins/calc): the first tool in the tool slot. Ported from r4to's calculator shortcuts
/// (PR #85, BOAR R&D, MIT; BoarRouting CalcShortcut, Arithmetic, NumGuard): a calculation in the question is answered
/// exactly, with its formula, and the model never runs. Never on a chat that names health, an injury, danger or a person
/// (NumGuard's lexicon, over this and the earlier user turns): those stay with the model.
struct CalcLab: LabPlugin {
    let id = "calc"
    let order = 65
    let emoji = "🧮"
    let art: String? = "lab_calc"
    let status = LabStatus.beta
    var title: String { String(localized: "Calculator") }
    var body: String { String(localized: "Exact answers to everyday sums: fuel, battery, currency and more. No model needed.") }
    var answerTool: (any AnswerTool)? { Tool() }

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            LabTools.calc(query, userTurns: history.filter { $0.role == "user" }.map(\.text)).map { .instant(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(AnswerPage(
            summary: String(localized: "Exact answers to everyday sums and unit conversions, with the formula. No model needed."),
            question: String(localized: "My rental car uses 7.5 litres per 100 km. How much is that in US miles per gallon?"),
            reply: String(localized: "7.5 L/100 km = 31.36 miles per gallon (US gallon). Formula: mpg = 235.215 ÷ L/100 km."),
            tries: [String(localized: "I have 23 L of water and 5 L jerrycans. How many jerrycans do I need?"),
                    String(localized: "How long to drive 240 miles at 60 mph?"),
                    String(localized: "26 miles in km")],
            how: String(localized: "• Works out the answer from the numbers in your question and shows the formula.\n• Converts miles, km, feet, inches, yards, kg, lb, ounces, US gallons and °C/°F: \"26 miles in km\".\n• Anything else goes to the model as usual.\n• It stays out of conversations about health, injuries, danger or people.\n• The answer's details say Tool when the calculator wrote it.\n• Word problems are English only. Ported from r4to's calculator (BOAR R&D).")))
    }
}

/// A question to try, in quotes; long-press copies it.
struct LabExample: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) { self.text = text }

    var body: some View {
        Text(verbatim: "“\(String(localized: text))”")
            .font(.boar("ui.subtext"))
            .foregroundStyle(.boar(.muted))
            .textSelection(.enabled)
    }
}
