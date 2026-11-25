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
    var title: String { String(localized: "Facts") }
    var body: String { String(localized: "Quick facts on countries, cities, mountains and rivers.") }
    var answerTool: (any AnswerTool)? { Tool() }
    var searchStage: (any SearchStage)? { Stage() }

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

    /// A question naming two or more countries (and not answered at once above): the table's dated figures for them go to
    /// the model as one more numbered source, after the search's own (t9 0110 item 5). English names, as the table.
    struct Stage: SearchStage {
        func process(query: String, chunks: [Chunk], topK: Int) throws -> [Chunk] {
            let kept = Array(chunks.prefix(topK))
            guard let extra = FactsLab.table?.countryContext(query) else { return kept }
            return kept + [extra]
        }
    }

    func content() -> AnyView {
        AnyView(FactsPage())
    }
}

/// The template with what it knows in three groups (adam): Places, Measures, Other.
private struct FactsPage: View {
    var body: some View {
        Section {
            Text("Answers from a Wikidata table kept on the phone. English only for now.")
                .font(.boar("ui.bodyLg"))
                .foregroundStyle(.boar(.primary))
            group("Places", "population, area, capital, currency, languages, continent, borders")
            group("Measures", "height, length, depth; which of two places is bigger, higher, longer or has more people")
            group("Other", "when a monument was built, plugs and voltage, where an event happened, who won a prize in a year")
            Text("Every answer shows its source and date (Wikidata, October 2026).")
                .font(.boar("ui.caption"))
                .foregroundStyle(.boar(.muted))
        }
        AnswerPage(
            question: String(localized: "What is the capital of Kenya?"),
            reply: String(localized: "The capital of Kenya is Nairobi.\n\nSource: Wikidata (CC0), offline table as of 2026-10-06."),
            tries: [String(localized: "Does Brazil have more people than Russia?"),
                    String(localized: "What plug type and voltage does Brazil use?"),
                    String(localized: "If you stood the Burj Khalifa on the deepest point of Lake Baikal, would its top stick out of the water?")],
            how: String(localized: "• Answers from a Wikidata table kept on the phone, English only for now.\n• Two facts at once, a summary, a why or how, an ambiguous name (Georgia) or a health conversation go to the model.\n• An older population shows its year.\n• Every answer shows its source and date (Wikidata, October 2026).\n• Offline data from r4to (BOAR R&D)."))
    }

    private func group(_ title: LocalizedStringKey, _ list: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.boar("ui.body").weight(.semibold)).foregroundStyle(.boar(.heading))
            Text(list).font(.boar("ui.body")).foregroundStyle(.boar(.secondary))
        }
    }
}
