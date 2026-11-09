import BoarAnswer
import SwiftUI

/// Boar Guard (android labs/plugins/guard): the verdict guard step of r4to's src/routing/answer.ts, around
/// src/routing/verdictGuard.ts (PR #85, BOAR R&D, MIT; BoarRouting `VerdictGuard`), in the check slot. After the model
/// answers, a Yes/No or a winner that the answer's own figures or dates contradict ("No, astronauts did not walk on the
/// Moon before 1970. The first moonwalk was on July 20, 1969") is rewritten from those figures; anything it isn't sure of
/// stays as written. English only; never a health question (answer.ts skips its health route), and an answer with a
/// thinking block is left alone.
struct GuardLab: LabPlugin {
    let id = "guard"
    let order = 68
    let emoji = "🛡️"
    let art: String? = "lab_guard"
    let status = LabStatus.alpha
    var title: String { String(localized: "Boar Guard") }
    var body: String { String(localized: "Fixes a Yes, No or winner that the model's own figures or dates contradict, after it answers.") }
    var answerCheck: (any AnswerCheck)? { Check() }

    struct Check: AnswerCheck {
        func check(question: String, answer: String) -> Repair? {
            LabTools.guard(question: question, answer: answer).map { Repair(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(Group {
            Section {
                Text("• Before or after a year: a No next to the answer's own first date that says Yes\n• Which is bigger, denser, taller or heavier, A or B: a winner the answer's own numbers in the same unit disagree with\n• Which are bigger than X: \"none\" next to \"X is the seventh-largest\"")
            } header: {
                Text("Checks")
            }
            Section {
                LabExample("Did astronauts walk on the Moon before 1970?")
                LabExample("Which is more densely populated, Japan or Germany, and by how much?")
                LabExample("Which countries are bigger than India by area?")
            } header: {
                Text("Try")
            } footer: {
                BoarFooter {
                    Text("It only reads the finished answer, so you see the model's text while it is written and the fixed one when it ends. The facts stay and the wrong verdict is rewritten from them, with the model's own corrections and restatements removed; nothing is generated again. It leaves the answer alone when it isn't sure: mixed units, overlapping ranges, a number that may belong to something else. Never on health questions, instant answers or Deep Research. The answer's details say Tool when it changed something. English only. Ported from r4to's verdict guard (BOAR R&D).")
                }
            }
        })
    }
}
