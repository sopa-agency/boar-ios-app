import BoarRAG
import BoarRouting
import Foundation

/// Conversation history that fits a token budget, for the answer prompt (port of src/routing/historyBudget.ts).
///
/// The chat sent the last 6 messages verbatim; with detailed answers the history alone grew to ~1,700 tokens, read again
/// for every question. Newest turns first, within `budgetTokens`: a question is kept whole, an earlier answer is cut to
/// its opening sentences (`answerTokens`), and the latest exchange always goes in, even over budget.
public enum HistoryBudget {
    public static let budgetTokens = 400
    public static let answerTokens = 80

    /// The opening sentences of `text` within `maxTokens`; at least the first sentence, cut by characters if it alone is too long.
    public static func leadSentences(_ text: String, maxTokens: Int, count: (String) -> Int = Compress.approxTokens) -> String {
        if count(text) <= maxTokens { return text }
        let sentences = Compress.splitSentences(text)
        var out = ""
        for s in sentences {
            let next = out.isEmpty ? s : "\(out) \(s)"
            if count(next) > maxTokens { break }
            out = next
        }
        if out.isEmpty {
            let first = sentences.first ?? text
            let n = min(max(maxTokens * 4, 0), first.u16)
            out = JsString.trimEnd(first.u16Take(n))
        }
        return "\(out) …"
    }

    public static func budget(
        _ turns: [ConversationTurn], budgetTokens: Int = HistoryBudget.budgetTokens, answerTokens: Int = HistoryBudget.answerTokens,
        count: (String) -> Int = Compress.approxTokens
    ) -> [ConversationTurn] {
        var kept: [ConversationTurn] = []
        var used = 0
        for t in turns.reversed() {
            let text = t.role == "assistant" ? leadSentences(t.text, maxTokens: answerTokens, count: count) : t.text
            let cost = count(text)
            // The latest exchange (one question and its answer) always goes in.
            if used + cost > budgetTokens && kept.count >= 2 { break }
            kept.insert(ConversationTurn(role: t.role, text: text), at: 0)
            used += cost
        }
        return kept
    }
}
