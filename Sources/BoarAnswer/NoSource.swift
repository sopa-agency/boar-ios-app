import BoarRouting

/// The line under a model's answer when nothing in the library backs it (port of NoSource.kt; t9 0110 item 6, 0226 point
/// 4; the texts are t9's and adam may change them): the search ran and found nothing, no plugin answered, and the answer
/// cites nothing. Never under small talk ("hey, what's up?" isn't looked up) or a plugin's instant answer.
public enum NoSource {
    /// `style`: the receipt's answer style. Personal Files with nothing found writes its own fixed line, no model ran, so
    /// "the answer is from the model alone" would be false under it (validator R-C11). With 0 sources a [1] in the answer is
    /// made up (or code like items[1]): it no longer hides the line (R-C12).
    public static func shows(searched: Bool, sources: Int, instant: Bool, question: String, answer: String, style: String? = nil) -> Bool {
        searched && sources == 0 && !instant && !answer.allSatisfy(\.isWhitespace) && !PersonalFiles.isOn(style) && !ShortAnswer.isSmallTalk(question)
    }
}
