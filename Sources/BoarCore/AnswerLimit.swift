/// An answer that ended at its token limit rather than by itself, and the next limit to retry it with
/// (android `engine/settings/AnswerLimit.kt`).
public enum AnswerLimit {
    /// Streamed pieces can count a token or two short of what the engine generated (bytes merged into one piece).
    public static func reached(generated: Int, limit: Int) -> Bool {
        limit > 0 && generated >= limit - 2
    }

    /// The next length in Settings above `limit` that still leaves room for the prompt; nil when none does.
    public static func next(after limit: Int, options: [Int], openedContext: Int?) -> Int? {
        options.sorted().first { $0 > limit && (openedContext == nil || $0 <= openedContext! - AppSettings.promptReserve) }
    }
}
