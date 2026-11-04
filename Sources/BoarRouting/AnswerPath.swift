/// Which way the chat answers a message (port of AnswerPath.kt).
public enum AnswerPath: String, Sendable, Equatable {
    /// Deep Research: sub-questions, a search for each, one write-up.
    case research
    /// A recap or summary of this chat, written by Deep Research from the conversation.
    case recap
    /// The adaptive router picks a model and a plan.
    case adaptive
    /// The plain answer pipeline (it skips the library for small talk).
    case pipeline

    /// Small talk ("hi", "oi", "thanks") always takes the plain pipeline: no Deep Research, no router, no library, at
    /// Succinct's length. Under Deep Research a 35B spent over three minutes splitting "hi" into sub-questions (Oct 20).
    public static func of(deepResearch: Bool, aboutConversation: Bool, adaptive: Bool, smallTalk: Bool) -> AnswerPath {
        if smallTalk { return .pipeline }
        if deepResearch { return .research }
        if aboutConversation { return .recap }
        if adaptive { return .adaptive }
        return .pipeline
    }

    /// A thank-you or greeting (ShortAnswer.isSmallTalk): a short reply.
    public static func isSmallTalk(_ question: String) -> Bool { ShortAnswer.isSmallTalk(question) }
}
