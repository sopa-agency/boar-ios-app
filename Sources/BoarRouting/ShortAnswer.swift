import Foundation

/// Why a question picked under Detailed is answered in Succinct instead (port of ShortAnswer.kt): "health" (first aid,
/// symptoms) or "seed" (seed phrases, wallet backups), else nil. A follow-up in such a chat counts too ("and for how
/// long?" after a burn question): it doesn't name the topic, but the answer is still first aid (r4to, Oct 18).
public enum ShortAnswer {
    /// The reminder a Local Files health answer gets, after its own: kept short like Succinct.
    public static let personalShort = "Keep it short: 3 to 5 sentences."

    /// A thank-you or greeting ("thanks, that helps"): a short reply, with no note under it.
    public static let smallTalk = "smalltalk"

    /// Local Files ("personal") is kept short too for health (a blood-test file's summary ran long and read the results
    /// wrong); it keeps its own files-only prompt with a short reminder (`personalShort`).
    public static func reason(chosenStyle: String, question: String, previousQuestion: String?) -> String? {
        if chosenStyle == "personal" {
            let r = reasonFor(question) ?? previousQuestion.flatMap(reasonFor)
            return r == "health" ? r : nil
        }
        if chosenStyle != "detailed" { return nil }
        // Before the follow-up check: "thanks" after a burn question is small talk, not first aid.
        if isSmallTalk(question) { return smallTalk }
        return reasonFor(question) ?? previousQuestion.flatMap(reasonFor)
    }

    /// Small talk answers in Succinct, at most its 512 tokens, not a Detailed essay (Oct 18, X6).
    public static func isSmallTalk(_ question: String) -> Bool { Classify.classifyTask(question) == .greeting }

    private static func reasonFor(_ q: String) -> String? {
        if QueryContext.isHealthQuestion(q) { return "health" }
        if QueryContext.isSeedPhraseQuestion(q) { return "seed" }
        return nil
    }
}
