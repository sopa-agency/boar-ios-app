import BoarRAG
import Foundation

/// The Personal Files answer style ("personal"): answers only from the user's own files (port of PersonalFiles.kt). The
/// one place the chat decides what the style changes. The owner's choices (Oct 21): nothing found means the fixed line,
/// never an answer from memory; no Deep Research, adaptive routing or answer check.
public enum PersonalFiles {
    public static let style = "personal"

    /// The answer when nothing in the user's files matched (the chat shows its own language's line).
    public static let notFound = "I couldn't find this in your Personal Files."

    public static func isOn(_ style: String?) -> Bool { style == Self.style }

    /// A Labs tool's answer is kept only from a safety card (`safety-*`), as under Deep Research.
    public static func keepsTool(_ toolId: String) -> Bool { toolId.hasPrefix("safety-") }

    /// `base` (the user's or the run's ranking) kept to the user's own files.
    public static func retrieval(_ base: RetrievalParams = .default) -> RetrievalParams {
        var p = base
        p.ownOnly = true
        return p
    }

    /// `base` as this style sends it: whole parts within `contextSize` (the context the model was opened with), the
    /// files-only instruction, `notFound` written without the model when nothing is found, and `filesNote`, the list of
    /// the user's switched-on files (OwnFiles.note).
    public static func request(_ base: AnswerRequest, contextSize: Int, notFound: String = notFound, filesNote: String? = nil) -> AnswerRequest {
        var r = base
        r.filesOnly = true
        r.contextSize = contextSize
        r.notFoundText = notFound
        r.filesNote = filesNote
        return r
    }

    /// An answer this long after the not-found line is a real answer, not a sign-off.
    public static let answerAfterHedgeChars = 40
    private static let lead = Rx("^(however|but|that said|still|nevertheless)[,:]?[ \\t\\n\\x0B\\f\\r]+", ignoreCase: true)
    private static let citation = Rx("\\[[0-9]+]")

    /// A small model sometimes opens with `notFound` "to be safe" and then answers from the files anyway ("I couldn't find
    /// this in your Personal Files. According to your blood test…", Oct 22): one or the other, never both. The line goes
    /// only when what follows cites the user's files ([1], [2]…). Without a citation the rest may come from memory, so the
    /// line stays as the honest signal; so does a line on its own or with a short sign-off.
    public static func dropHedge(_ answer: String) -> String {
        let t = String(answer.drop(while: \.isWhitespace))
        if !t.hasPrefix(notFound) { return answer }
        let rest = String(t.dropFirst(notFound.count).drop(while: \.isWhitespace))
        if rest.u16 < answerAfterHedgeChars || !citation.containsMatch(in: rest) { return answer }
        let body = lead.replaceFirst(rest, with: "")
        guard let first = body.first else { return body }
        return first.uppercased() + body.dropFirst()
    }
}
