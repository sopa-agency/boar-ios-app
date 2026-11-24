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
    var title: String { String(localized: "Guard") }
    var body: String { String(localized: "Fixes a yes, no or winner that the model's own numbers contradict.") }
    var answerCheck: (any AnswerCheck)? { Check() }

    struct Check: AnswerCheck {
        func check(question: String, answer: String) -> Repair? {
            LabTools.guard(question: question, answer: answer).map { Repair(tool: $0.tool, text: $0.text) }
        }
    }

    func content() -> AnyView {
        AnyView(PluginPage(
            summary: String(localized: "Guard checks a finished answer against its own numbers and fixes a Yes, No or winner that they contradict."),
            before: String(localized: "“Did astronauts walk on the Moon before 1970?” → “No. Apollo 11 landed on the Moon on July 20, 1969.”"),
            after: String(localized: "“Yes. Apollo 11 landed on the Moon on July 20, 1969.” The answer’s own date says Yes, so Guard fixes the No."),
            tries: [String(localized: "Did astronauts walk on the Moon before 1970?"),
                    String(localized: "Which is more densely populated, Japan or Germany, and by how much?"),
                    String(localized: "Which countries are bigger than India by area?")],
            how: String(localized: "• Guard waits for the answer to finish.\n• You see the model's text as it writes, then the fixed one.\n• It checks three things:\n• Before or after a year: the Yes or No against the answer's own first date.\n• Which is bigger, denser, taller or heavier: the winner against the answer's own numbers, in the same unit.\n• It adds the difference.\n• Which are bigger than X: “none” against the answer's own rank (“seventh-largest” means six).\n• It keeps the facts and rewrites only the verdict, dropping the model's own corrections and repeats.\n• Nothing is generated again.\n• When it isn't sure, it changes nothing: mixed units, overlapping ranges, a number that may belong to something else.\n• Never on health questions, instant answers or Deep Research.\n• The answer's details say Tool when it changed something.\n• English only.\n• Based on r4to's verdict guard (BOAR R&D).")))
    }
}
