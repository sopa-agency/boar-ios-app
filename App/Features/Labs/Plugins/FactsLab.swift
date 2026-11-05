import BoarAnswer
import BoarRAG
import os
import SwiftUI

/// Boar Facts (android labs/plugins/facts): the FACTS step of r4to's src/routing/answer.ts, around src/rag/facts.ts
/// (PR #85, BOAR R&D, MIT; BoarAnswer `Facts`). A question that names a place, landmark, event or award in the Wikidata
/// table (App/Resources/Data, CC0) and asks one property of it gets the value with its source line, or a computed verdict
/// for two of them, and the model never runs. English only; QueryContext's health detector, over this and the earlier
/// user turns, keeps it off health.
struct FactsLab: LabPlugin {
    let id = "facts"
    let order = 67
    let emoji = "📇"
    let art: String? = "lab_facts"
    let status = LabStatus.beta
    var title: String { String(localized: "Boar Facts") }
    var body: String { String(localized: "One fact about a country, city, mountain, river, landmark or award, from a Wikidata table, without the model.") }
    var answerTool: (any AnswerTool)? { Tool() }

    /// The fact table, read on the first question (780 KB of JSON).
    nonisolated static let table: Facts? = {
        guard let url = Bundle.main.url(forResource: "lab_facts_facts_v1", withExtension: "json") else { return nil }
        do {
            return try Facts(json: Data(contentsOf: url))
        } catch {
            Logger(subsystem: "team.sopa.boar", category: "labs").error("facts table: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            LabTools.facts(FactsLab.table, query, userTurns: history.filter { $0.role == "user" }.map(\.text))
                .map { .instant(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(Group {
            Section {
                Text("• Population, area, capital, currency, official languages, continent and borders\n• Height or elevation, length and depth\n• When a landmark was built or came down\n• Plug types and mains voltage\n• Where an event was held, and an award's winner in a given year\n• Two places compared: which is bigger, taller, longer or has more people")
            } header: {
                Text(LocalizedStringResource("labs.facts.answers", defaultValue: "Answers on its own"))
            }
            Section {
                LabExample("Does Brazil have more people than Russia?")
                LabExample("What plug type and voltage does Brazil use?")
                LabExample("If you stood the Burj Khalifa on the deepest point of Lake Baikal, would its top stick out of the water?")
            } header: {
                Text("Try")
            } footer: {
                Text("It answers only when the question names something in the table and asks for exactly one of these; every answer ends with its source and the table's date (Wikidata, CC0, October 2026), and an older population figure says how old it is. Two properties at once, an overview, a why or how question, a name it can't tell apart (Georgia), or a chat about health goes to the model as usual. Questions in English only. Ported from r4to's offline facts (BOAR R&D).")
            }
        })
    }
}
