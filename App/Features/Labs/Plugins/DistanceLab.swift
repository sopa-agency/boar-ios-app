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
    var title: String { String(localized: "Distance") }
    var body: String { String(localized: "How far apart two cities are, and how long the trip takes.") }
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
        AnyView(AnswerPage(
            question: String(localized: "What's the distance between Madrid and Barcelona?"),
            reply: String(localized: "Madrid and Barcelona are about 504 km (313 miles) apart in a straight line. Roads and trails are usually longer than the straight line, by about a quarter, so expect roughly 630 km by land. This is an estimate from the cities' coordinates, not a mapped route; the real route can differ."),
            tries: [String(localized: "How far is it to walk from Paris to Rome and back?"),
                    String(localized: "How long would it take to bike from Vienna to Budapest?"),
                    String(localized: "How long to drive from Berlin to Prague?")],
            how: String(localized: "• Works from the 6,000 largest cities (GeoNames), using their coordinates.\n• Every answer is an estimate, not a route: no roads, borders, ferries or closures.\n• A place that is not one of those cities (a hotel, a beach, a small town) goes to the model.\n• A chat about health, an injury or danger goes to the model.\n• English only. Ported from r4to's travel distance (BOAR R&D).")))
    }
}
