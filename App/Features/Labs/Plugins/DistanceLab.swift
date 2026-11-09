import BoarAnswer
import BoarRAG
import BoarRouting
import os
import SwiftUI

/// Boar Distance (android labs/plugins/distance): the travel distance step of r4to's src/routing/answer.ts, around
/// src/routing/travelDistance.ts (PR #85, BOAR R&D, MIT; BoarRouting `TravelDistance`). "How far is it to walk from Paris
/// to Rome and back?" gets the straight-line distance between two cities in the GeoNames table (App/Resources/Data,
/// CC BY 4.0) times a stated route factor, always called an estimate, and the model never runs. English only; NumGuard's
/// health lexicon over this and the earlier user turns keeps it off health.
struct DistanceLab: LabPlugin {
    let id = "distance"
    let order = 66
    let emoji = "🗺️"
    let art: String? = "lab_distance"
    let status = LabStatus.beta
    var title: String { String(localized: "Boar Distance") }
    var body: String { String(localized: "How far apart two cities are, and how long to walk, cycle or drive it, as an estimate and without the model.") }
    var answerTool: (any AnswerTool)? { Tool() }

    /// The city table, read on the first travel question (280 KB of JSON).
    nonisolated static let table: TravelDistance? = {
        guard let url = Bundle.main.url(forResource: "lab_distance_world_cities_v1", withExtension: "json") else { return nil }
        do {
            return try TravelDistance(json: Data(contentsOf: url))
        } catch {
            Logger(subsystem: "team.sopa.boar", category: "labs").error("city table: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            LabTools.distance(DistanceLab.table, query, userTurns: history.filter { $0.role == "user" }.map(\.text))
                .map { .instant(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(Group {
            Section {
                Text("• The straight-line distance between two cities, in km and miles\n• Roughly how far by road or trail: walking about 30% longer, cycling and driving about 25%\n• How many days to walk or cycle it, or hours to drive\n• There and back, when you ask for the round trip")
            } header: {
                Text(LocalizedStringResource("labs.answersOnItsOwn.m", defaultValue: "Answers on its own", comment: "Header; PT is masculine (Boar Fatos, Boar Distância)"))
            }
            Section {
                LabExample("How far is it to walk from Paris to Rome and back?")
                LabExample("How long would it take to bike from Vienna to Budapest?")
                LabExample("What's the distance between Madrid and Barcelona?")
            } header: {
                Text("Try")
            } footer: {
                BoarFooter {
                    Text("It knows the 6,000 largest cities (GeoNames, CC BY 4.0) and works from their coordinates, so every answer is an estimate, not a mapped route: it can't know roads, borders, ferries or closures. A place that isn't one of those cities (a hotel, a beach, a small town) goes to the model as usual, and so does a chat about health, an injury or danger. Questions in English only. Ported from r4to's travel distance (BOAR R&D).")
                }
            }
        })
    }
}
