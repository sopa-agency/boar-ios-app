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
    var title: String { String(localized: "Boar Calculator") }
    var body: String {
        String(localized: "Exact answers to a few everyday calculations (battery, fuel, hiking, currency, water, temperature, how long, how many), instantly and without the model. Plain sums and percentages still go to the model.")
    }
    var answerTool: (any AnswerTool)? { Tool() }

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            LabTools.calc(query, userTurns: history.filter { $0.role == "user" }.map(\.text)).map { .instant(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(Group {
            Section {
                Text("• A battery's watt-hours, and whether it can fly\n• Fuel economy: L/100 km and miles per gallon\n• Hiking time by Naismith's rule\n• Currency at the rate you give, with a tip\n• Water for a trip: people × days × litres\n• Temperature: Celsius and Fahrenheit\n• How long: an amount at a rate (MB at MB/s, km at km/h, pages per hour)\n• How many: containers, trips or buses for a total, rounded up")
            } header: {
                Text("Answers on its own")
            }
            Section {
                LabExample("I have 23 L of water and 5 L jerrycans. How many jerrycans do I need?")
                LabExample("How long to drive 240 miles at 60 mph?")
                LabExample("My power bank is 5,000 mAh at 3.85 V. How many watt-hours is that, and can I take it on a plane?")
            } header: {
                Text("Try")
            } footer: {
                Text("It works out the answer from the numbers in your question and shows the formula. Anything else goes to the model as usual. A message about health, an injury, danger or a person (or a chat that was) never gets a calculator answer. The answer's details say Tool when the calculator wrote it. Word problems are English only. Ported from r4to's calculator (BOAR R&D).")
            }
        })
    }
}

/// A question to try, in quotes; long-press copies it.
struct LabExample: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) { self.text = text }

    var body: some View {
        Text(verbatim: "“\(String(localized: text))”")
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
