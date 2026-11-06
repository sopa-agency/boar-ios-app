import BoarAnswer
import BoarRAG
import BoarRouting
import NaturalLanguage
import SwiftUI

/// Boar Polyglot (android labs/plugins/polyglot): a full question in a language BOAR doesn't answer in (anything but
/// English, Portuguese and, for now, Spanish: `LanguageGate.allowed`) gets an instant reply saying so, in the app's
/// language, and the model never runs. The decision is BoarRouting `LanguageGate`; the device's language detector
/// (NaturalLanguage, where Android asks TextClassifier) is asked only for Latin-script text, and other scripts are told
/// by their letters. Second in the tool slot, after Boar Cohazard.
struct PolyglotLab: LabPlugin {
    let id = "polyglot"
    let order = 64
    let emoji = "🗣️"
    let art: String? = "lab_polyglot"
    let status = LabStatus.beta
    var title: String { String(localized: "Boar Polyglot") }
    var body: String { String(localized: "Says so at once when you ask in a language BOAR doesn't speak yet, instead of a confused answer.") }
    var answerTool: (any AnswerTool)? { Tool() }

    struct Tool: AnswerTool {
        func run(query: String, history: [ConversationTurn]) -> ToolResult? {
            let decision = LanguageGate.decide(query, followUp: Self.followUp(history)) { Self.detect($0) }
            guard case .unsupported(let code) = decision else { return nil }
            return .instant(tool: LanguageGate.tool, text: Self.reply(Self.languageName(code)))
        }

        static func reply(_ language: String) -> String {
            String(localized: "Sorry, BOAR doesn't speak \(language) yet. Ask in English.")
        }

        /// The last question in this chat was answered (not with this reply): a short message now is a follow-up to it.
        static func followUp(_ history: [ConversationTurn]) -> Bool {
            guard let lastUser = history.lastIndex(where: { $0.role == "user" }), lastUser + 1 < history.count else { return false }
            let next = history[lastUser + 1]
            guard next.role == "assistant", !next.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let ours = reply("\u{0}").components(separatedBy: "\u{0}")[0]
            return ours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !next.text.hasPrefix(ours)
        }

        /// The app's language (iOS Settings → BOAR → Language, else the system's).
        static var uiLocale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

        /// The language's name in the app's language: "Russian"; in Portuguese lowercase, as it writes them ("russo").
        static func languageName(_ code: String) -> String {
            let ui = uiLocale
            let name = ui.localizedString(forLanguageCode: code).flatMap { $0.isEmpty ? nil : $0 } ?? code
            return ui.language.languageCode?.identifier == "pt" ? name.lowercased(with: ui) : name
        }

        /// The device's language detector: its best guesses for the cleaned text, best first.
        static func detect(_ text: String) -> LanguageGate.Guesses? {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let guesses = recognizer.languageHypotheses(withMaximum: 5)
                .map { ($0.key.rawValue, Float($0.value)) }
                .sorted { $0.1 > $1.1 }
            return guesses.isEmpty ? nil : guesses
        }
    }

    func content() -> AnyView {
        AnyView(Group {
            Section {
                Text("• A full question in a language other than English\n• Other alphabets by their letters: Russian, Ukrainian, Chinese, Japanese, Korean, Arabic, Hebrew, Hindi, Thai, Greek and more\n• Languages in the Latin alphabet (French, German, Italian, Dutch, Polish, Turkish) when the language detector is sure")
            } header: {
                Text("Replies on its own")
            }
            Section {
                LabExample("Как долго нужно кипятить воду, чтобы она была безопасной?")
                LabExample("烧水需要多长时间才能安全饮用？")
                LabExample("Wie lange dauert es, bis das Wasser kocht?")
            } header: {
                Text("Try")
            } footer: {
                Text("Short messages, thanks and greetings, names, quotes, code and links go to the model as usual, and so does a question with English in it (What does 'merci' mean?). A short follow-up in a chat already going goes to the model too. The answer's details say Tool: language.")
            }
        })
    }
}
