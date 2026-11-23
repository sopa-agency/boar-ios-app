import BoarRouting
import Foundation

/// "Merge" on the queue (adam, Nov 12): the waiting questions become one, answered together in one answer. The model
/// writes that answer as usual, so no extra model run happens now (one at 4 to 5 tokens a second would delay the queue).
/// A merged question goes to the model, never to a plugin's instant answer, which would answer one part and drop the
/// others (validator Q-8; the chat's send checks `isMerged`). Android `engine/chat/PromptMerge.kt`.
public enum PromptMerge {
    private static let en = "Answer these questions together, in one answer that covers each of them:"
    private static let pt = "Responda a estas perguntas juntas, numa só resposta que trate de cada uma:"
    private static let es = "Responde a estas preguntas juntas, en una sola respuesta que trate cada una:"
    private static let heads = [en, pt, es]

    public static func of(_ questions: [String]) -> String {
        // Merging a merged question again keeps one flat list, not a list inside a list (validator Q-9).
        let qs = questions.flatMap(parts).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if qs.count <= 1 { return qs.first ?? "" }
        let head: String
        let portuguese = qs.count(where: QueryContext.isPortugueseQuestion)
        if portuguese * 2 > qs.count
            // Half Portuguese and none Spanish: the Portuguese head (validator Q-9: a PT pair with one miss got English).
            || (portuguese * 2 == qs.count && !qs.contains(where: QueryContext.isSpanishQuestion)) {
            head = pt
        } else if qs.count(where: QueryContext.isSpanishQuestion) * 2 > qs.count {
            head = es
        } else {
            head = en
        }
        return head + "\n" + qs.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    /// A safety card for a merged text that still matches it (hazard words spread over two questions; a safety question
    /// itself is never merged, `PromptQueue.merge`): never silent context, the model is told to state it first, unchanged
    /// (validator M-1/N-2).
    public static func safetyContext(_ card: String) -> String {
        "SAFETY WARNING. Start your answer with this warning, word for word, before anything else, then answer the questions:\n\(card)"
    }

    /// A merged question goes to the model whole: an instant answer would take one question and drop the rest (validator
    /// Q-8). A safety answer isn't lost: the model reads it first, to state before anything else. Nil: no tool answers it.
    public static func forModel(_ result: ToolResult, question: String) -> ToolResult? {
        guard case .instant(let tool, let text) = result, isMerged(question) else { return result }
        return tool.hasPrefix("safety-") ? .context(tool: tool, text: safetyContext(text)) : nil
    }

    public static func isMerged(_ text: String) -> Bool {
        let t = text.drop(while: \.isWhitespace)
        return heads.contains { t.hasPrefix($0) }
    }

    /// The questions inside a merged text; the text itself otherwise.
    public static func parts(_ text: String) -> [String] {
        guard isMerged(text) else { return [text] }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/^[0-9]+\.[ ]/, with: "") }
            .filter { !$0.isEmpty }
    }
}
