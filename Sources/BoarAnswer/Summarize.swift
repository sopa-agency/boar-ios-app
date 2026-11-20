import BoarRAG
import BoarRouting
import Foundation

/// Chat titles and running summaries (port of src/services/summarize.ts), with the same prompts and settings.
public enum Summarize {
    private static let titleInstruction =
        "Generate a short 3-5 word title (no punctuation, no quotes) for a chat that starts with the user's message. Reply with the title only."
    private static let summaryInstruction =
        "Summarize the key facts, constraints, and user preferences from this conversation into 2-3 bullet points."
    private static let edgeQuote = Rx("^[\"']|[\"']\\z")

    /// generateSessionTitle's clean-up: first line, edge quotes removed, at most 60 characters; "New chat" when empty.
    public static func cleanTitle(_ text: String) -> String {
        let stripped = edgeQuote.replace(JsString.trim(text), with: "")
        let line = stripped.components(separatedBy: "\n")[0].u16Take(60)
        return line.isEmpty ? "New chat" : line
    }

    public static func title(_ generator: any StageGenerator, firstUserMessage: String, timeoutMs: Int64? = nil) async throws -> String {
        let r = try await generator.generate(system: titleInstruction, user: titleInput(firstUserMessage), nPredict: 16, temperature: 0.3, timeoutMs: timeoutMs, onToken: nil)
        return cleanTitle(r.text)
    }

    /// The title's input: the quoted message, and for a Portuguese chat r4to's short line after it (t9 0420: what the user
    /// reads is in the user's language; the drawer shows the title). English input is as before.
    public static func titleInput(_ firstUserMessage: String) -> String {
        let line = AnswerLanguage.line(AnswerLanguage.of(firstUserMessage), withSources: false)
        return "\"\(firstUserMessage)\"" + (line.map { "\n\n\($0)" } ?? "")
    }

    public static func summary(_ generator: any StageGenerator, turns: [ConversationTurn], previousSummary: String?, timeoutMs: Int64? = nil) async throws -> String {
        let transcript = turns.map { "\($0.role == "user" ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n")
        let prefix = (previousSummary?.isEmpty == false) ? "Existing summary:\n\(previousSummary!)\n\n" : ""
        let r = try await generator.generate(system: summaryInstruction, user: prefix + transcript, nPredict: 150, temperature: 0.3, timeoutMs: timeoutMs, onToken: nil)
        return JsString.trim(r.text)
    }
}
