import BoarAnswer
import BoarRAG
import SwiftUI

/// Boar Cohazard (android labs/plugins/cohazard): the CO hazard step of r4to's src/routing/answer.ts, around
/// src/routing/coHazard.ts (PR #85, BOAR R&D, MIT; BoarRouting `CoHazard`). A planning question about a generator,
/// grill, camping stove, fuel heater or engine in a garage, tent, camper or home gets a fixed carbon monoxide answer,
/// reviewed and sourced (CDC, US CPSC, NHS), and the model never runs: a model answered "yes, with ventilation". English,
/// and Portuguese and Spanish with draft translations (not yet reviewed). Symptoms or an alarm go to the model as a health
/// question. First in the tool slot, and its answer has no "Ask BOAR instead".
struct CoHazardLab: LabPlugin {
    let id = "cohazard"
    let order = 69
    let emoji = "⚠️"
    let art: String? = "lab_cohazard"
    let status = LabStatus.beta
    var title: String { String(localized: "Cohazard") }
    var body: String { String(localized: "A fixed safety answer about carbon monoxide indoors.") }
    var answerTool: (any AnswerTool)? { Tool() }

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            LabTools.coHazard(query).map { .instant(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(CoHazardPage())
    }
}

/// A safety page: what to do now comes first, in amber, before the example (android CoHazardLab).
private struct CoHazardPage: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            Text(verbatim: "⚠ " + String(localized: "Headache, dizziness, nausea or confusion near a fuel-burning device, or a CO alarm going off, even without symptoms? Get everyone into fresh air now and call emergency services."))
                .font(.boar("ui.body").weight(.semibold))
                .foregroundStyle(.boar(.warning))
                .listRowBackground(Color(palette.amberBgSubtle))
        }
        AnswerPage(
            question: String(localized: "Can I run my portable generator in the attached garage if I keep the door open?"),
            reply: String(localized: "No. Carbon monoxide (CO) from a generator […] is a poison you can't see or smell, and it can kill in minutes. Never run them inside a home, garage, carport, basement, shed, tent or camper, even with the doors or windows open: that is not enough ventilation. Run a generator outside only, at least 20 feet (6 metres) from any door, window or vent…"),
            tries: [String(localized: "Can I run my portable generator in the attached garage if I keep the door open?"),
                    String(localized: "Is it safe to use a camping stove inside the tent to cook?"),
                    String(localized: "Can we bring the propane heater into the camper overnight?")],
            how: String(localized: "• It answers, without the model, when you plan to run a fuel-burning device indoors: a generator, a charcoal or gas grill, a camping stove or lantern, or a fuel heater in a home, garage, carport, basement, shed, tent or camper; an engine running in a garage; a gas oven or stove to heat a home; how far a generator must be from doors, windows and vents.\n• The answer is always the same reviewed text, with its sources (CDC, US CPSC, NHS) and an emergency number.\n• It starts with “No.” only when you ask whether you can do it.\n• Why it exists: small models told people a generator in a garage was fine with the door open.\n• Left to the model: electric heaters, installed and vented appliances, a propane stove in a kitchen.\n• Headaches, dizziness or an alarm going off are a health question, and BOAR answers them as one.\n• Questions in English, Portuguese or Spanish.\n• Based on r4to's CO hazard check (BOAR R&D)."))
    }
}
