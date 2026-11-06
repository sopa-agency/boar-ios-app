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
    var title: String { String(localized: "Boar Cohazard") }
    var body: String { String(localized: "A fixed carbon monoxide safety answer when you plan to run a fuel-burning device indoors, without the model.") }
    var answerTool: (any AnswerTool)? { Tool() }

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            LabTools.coHazard(query).map { .instant(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(Group {
            Section {
                Text("• A generator, charcoal or gas grill, camping stove or lantern, or fuel heater in a home, garage, carport, basement, shed, tent or camper\n• A car or other engine left running in a garage\n• Heating a home with a gas oven or stove\n• How far a generator must be from doors, windows and vents")
            } header: {
                Text(LocalizedStringResource("labs.answersOnItsOwn.m", defaultValue: "Answers on its own", comment: "Header; PT is masculine (Boar Fatos, Boar Distância)"))
            }
            Section {
                LabExample("Can I run my portable generator in the attached garage if I keep the door open?")
                LabExample("Is it safe to use a camping stove inside the tent to cook?")
                LabExample("Can we bring the propane heater into the camper overnight?")
            } header: {
                Text("Try")
            } footer: {
                Text("The answer is always the same reviewed text, with its sources (CDC, US CPSC, NHS) and an emergency number line; it starts with No. only when you ask whether you can do it. Small models told people a generator in a garage was fine with the door open. Electric heaters, installed and vented appliances and a propane stove in a kitchen are left to the model. A message about headaches, dizziness or an alarm going off is a health question and goes to the model as one. Ported from r4to's CO hazard check (BOAR R&D).")
            }
        })
    }
}
