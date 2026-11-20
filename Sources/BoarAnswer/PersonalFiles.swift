import BoarRAG
import Foundation

/// The Personal Files answer style ("personal"): answers only from the user's own files (port of PersonalFiles.kt). The
/// one place the chat decides what the style changes. The owner's choices (Oct 21): nothing found means the fixed line,
/// never an answer from memory; no Deep Research, adaptive routing or answer check.
public enum PersonalFiles {
    public static let style = "personal"

    /// The answer when nothing in the user's files matched (the chat shows its own language's line).
    public static let notFound = "I couldn't find this in your Personal Files."

    /// The same line in Portuguese (t9 0420), as the chat's own translation says it, so the model and the app name the
    /// files alike. Android says "Arquivos locais", its new name for them; this app keeps "Arquivos pessoais" until that
    /// rename comes over. AnswerLanguage.ptFilesOnly asks for it.
    public static let notFoundPT = "Não encontrei isso nos seus Arquivos pessoais."

    public static func isOn(_ style: String?) -> Bool { style == Self.style }

    /// The question asks for a summary: "summarize", "summary", "overview", "resuma", "resumo", "em resumo".
    private static let summary = Rx("(?<![\\p{L}])(?:summari[sz]e|summary|overview|sum up|resum[aeo]|resumir|em resumo|sintetize|panorama)(?![\\p{L}])", ignoreCase: true)
    public static func asksSummary(_ question: String) -> Bool { summary.containsMatch(in: question) }

    /// What a summary of the user's file asks of the model: its own words, never the file copied ("summarize" pasted a
    /// blood test, table and all), the file's numbers as written, and each result with the mark the code gave it
    /// (LabRanges), never its own comparison.
    public static let summaryEN = "This is a request for a summary: write 3 to 5 sentences in your own words; never copy the file or its table. "
        + "Give the file's numbers as it writes them. For each result that has a mark (WITHIN, ABOVE or BELOW its range), say that mark exactly; never compare numbers yourself."
    public static let summaryPT = "Isto é um pedido de resumo: escreva de 3 a 5 frases com suas palavras; nunca copie o arquivo ou a tabela. "
        + "Dê os números como o arquivo escreve. Para cada resultado com marcação (DENTRO, ACIMA ou ABAIXO da faixa), diga essa marcação exatamente; nunca compare números você mesmo."

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
    private static let lead = Rx("^(however|but|that said|still|nevertheless|por[ée]m|mas|no entanto|ainda assim|contudo|entretanto)[,:]?[ \\t\\n\\x0B\\f\\r]+", ignoreCase: true)
    private static let citation = Rx("\\[[0-9]+]")

    /// A small model sometimes opens with `notFound` "to be safe" and then answers from the files anyway ("I couldn't find
    /// this in your Personal Files. According to your blood test…", Oct 22): one or the other, never both. The line goes
    /// only when what follows cites the user's files ([1], [2]…). Without a citation the rest may come from memory, so the
    /// line stays as the honest signal; so does a line on its own or with a short sign-off.
    public static func dropHedge(_ answer: String) -> String {
        let t = String(answer.drop(while: \.isWhitespace))
        guard let hedge = [notFound, notFoundPT].first(where: { t.hasPrefix($0) }) else { return answer }
        let rest = String(t.dropFirst(hedge.count).drop(while: \.isWhitespace))
        if rest.u16 < answerAfterHedgeChars || !citation.containsMatch(in: rest) { return answer }
        let body = lead.replaceFirst(rest, with: "")
        guard let first = body.first else { return body }
        return first.uppercased() + body.dropFirst()
    }
}
