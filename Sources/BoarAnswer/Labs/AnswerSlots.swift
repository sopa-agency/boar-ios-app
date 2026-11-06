import BoarRAG

/// The tool slot (android `plugins/AnswerTools.kt`): a Boar Labs plugin looks at the question before the model runs (a
/// calculator, a lookup table) and either answers it itself or hands the model something to read first. The chat's
/// default and adaptive paths use it; Deep Research and answers about the conversation don't. With no tool, nothing
/// changes.
public protocol AnswerTool: Sendable {
    /// `history`: this chat's earlier turns, oldest first. Nil: not this tool's question.
    func run(query: String, history: [ConversationTurn]) throws -> ToolResult?
}

public enum ToolResult: Sendable, Equatable {
    /// The answer itself: shown as written, saved like a model's answer, no model call.
    case instant(tool: String, text: String)
    /// Read by the model before it answers, after the system prompt (a guard, a fact the tool worked out).
    case context(tool: String, text: String)

    /// Short and stable, kept in the answer's receipt ("calculator-battery").
    public var tool: String {
        switch self {
        case .instant(let tool, _), .context(let tool, _): tool
        }
    }

    /// The instant answer's text; nil for a context.
    public var instantText: String? {
        if case .instant(_, let text) = self { text } else { nil }
    }
}

public enum AnswerTools {
    /// The first tool with something to say; one that throws is skipped, as a search stage is.
    public static func run(_ tools: [any AnswerTool], query: String, history: [ConversationTurn]) -> ToolResult? {
        LabTools.first(tools) { try $0.run(query: query, history: history) }
    }

    /// The system prompt with a `.context`'s text after it; unchanged otherwise.
    public static func systemPrompt(_ base: String, _ result: ToolResult?) -> String {
        if case .context(_, let text) = result { return "\(base)\n\n\(text)" }
        return base
    }
}

/// The check slot (android `plugins/AnswerChecks.kt`): a Boar Labs plugin reads a model's finished answer with its
/// question and may return a repaired text (a verdict its own facts contradict). Only the chat's default and adaptive
/// paths call it, after generation and before the answer is saved (`LabTools.checksAnswer`).
public protocol AnswerCheck: Sendable {
    /// Nil: the answer stays as the model wrote it.
    func check(question: String, answer: String) throws -> Repair?
}

/// `tool`: short and stable, kept in the answer's receipt ("verdict-guard-date"); `text`: the answer that replaces it.
public struct Repair: Sendable, Equatable {
    public let tool: String
    public let text: String
    public init(tool: String, text: String) { self.tool = tool; self.text = text }
}

public enum AnswerChecks {
    /// The first check with a repair; one that throws is skipped, as a tool is.
    public static func run(_ checks: [any AnswerCheck], question: String, answer: String) -> Repair? {
        LabTools.first(checks) { try $0.check(question: question, answer: answer) }
    }
}
