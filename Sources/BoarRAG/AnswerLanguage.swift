import BoarRouting
import Foundation
import Synchronization

/// The language an answer is written in (port of AnswerLanguage.kt, t9 0420; adam, Nov 14: "the system prompt is all
/// time in english, even if user select portugueser… send language fix. all prompts"). r4to's fix of 29 Sep (the 4B
/// answered 8 of 29 Portuguese questions in English with English sources), lost when the Expo engine left: a line in
/// Portuguese, next to the question, with the citation request because "with the language line alone the models stopped
/// writing [n]". English prompts are unchanged.
///
/// Which language: the question's, when it's clear; else the conversation's last clear one; else the app's setting.
/// Here and not in BoarAnswer (Android's package) because RagPure, which writes every answer prompt, needs it.
public enum AnswerLanguage {
    /// `other`: clearly Spanish, French or German; no Portuguese line, the model answers as it would (validator C-1).
    public enum Lang: Sendable, Equatable { case en, pt, other }

    /// What the app sets: its language setting and the bench's arm. `phone` stands in for the phone's language in tests
    /// (nil: the real one).
    public struct Setting: Sendable, Equatable {
        public var app: String?
        public var arm: Int
        public var phone: String?
        public init(app: String? = nil, arm: Int = 1, phone: String? = nil) { self.app = app; self.arm = arm; self.phone = phone }
    }

    private static let shared = Mutex(Setting())

    /// A setting for the work inside `$scoped.withValue`, instead of the app's: tests run in parallel, so they never
    /// change the shared one.
    @TaskLocal public static var scoped: Setting?

    private static var current: Setting { scoped ?? shared.withLock { $0 } }

    /// The app's language setting ("pt", "en"), set by the app; the last word when nothing else tells.
    public static var appLanguage: String? {
        get { current.app }
        set { shared.withLock { $0.app = newValue } }
    }

    /// The language fix's arm (t9 0420 item 5), bench only until adam picks: 0 no line (the "before"); 1 the line next to
    /// the question (what users get); 2 also the style reminder in Portuguese; 3 also the style prompt in Portuguese
    /// (StylePt). English never moves.
    public static var arm: Int {
        get { current.arm }
        set { shared.withLock { $0.arm = newValue } }
    }

    /// r4to's lines (src/routing/context.ts:823-829), with adam's wording of the language (Nov 14: "use \"Responda em
    /// Português.\" instead \"Responda em português do Brasil.\""); the citation request stays word for word.
    public static let ptWithSources = "Responda em Português, mesmo que as fontes estejam em inglês, e cite cada afirmação com o número da fonte, como [1]."
    public static let ptNoSources = "Responda em Português."

    /// Personal Files' fixed line, in Portuguese, said exactly when the files don't hold it. It ends with
    /// PersonalFiles.notFoundPT (BoarAnswer) word for word; a test keeps the two equal.
    public static let ptFilesOnly = "Responda em Português e cite o arquivo pelo número, como [1]. Se o contexto não tiver a resposta, diga exatamente: "
        + "Não encontrei isso nos seus Arquivos locais."

    // Kotlin's Regex(IGNORE_CASE) on ICU: Unicode case folding, as Kotlin adds UNICODE_CASE.
    private static func re(_ pattern: String) -> Rx { Rx(pattern, .caseInsensitive) }

    // Words a Portuguese question doesn't use; one is enough once the Portuguese checks above said no (40 short questions,
    // Nov 14: two missed "What causes tides?" and "is it dangerous?").
    private static let enWords = re("\\b(the|is|are|was|were|what|how|why|who|which|when|where|does|did|of|and|to|in|can|should|would|tell|about|between|my|your|it|there|this|that|explain|thanks|thank|please|much|many|vs|height|best)\\b")

    // Spanish, French and German: words none of Portuguese or English uses ("es", "una", "pourquoi", "nicht"), two or
    // more, or a greeting alone (validator C-1: "hola" got "Responda em Português" in a Portuguese app).
    private static let esWords = re("(?<![\\p{L}])(qué|cómo|cuándo|dónde|por qué|es|una|un|mi|muy|tiene|puedo|hacer|están|el|los|las|del|al|y|pero|también|hola|gracias|cuál|cuánto|cuántos|hay)(?![\\p{L}])")
    private static let frWords = re("(?<![\\p{L}])(je|vous|nous|ce|le|est-ce|qu'est|pourquoi|quelle|quel|quels|quelles|les|avec|dans|sont|c'est|bonjour|merci|combien|très|ça|où|est|il|elle|pour|sur|une|des)(?![\\p{L}])")
    private static let deWords = re("(?<![\\p{L}])(ich|du|warum|wie|ist|sind|und|nicht|mit|eine|ein|der|den|dem|hallo|danke|bitte|welche|wieviel|wo|wer|was ist|kann|ich bin)(?![\\p{L}])")
    private static let greetingOther = re("^\\s*(?:¡?hola|bonjour|salut|hallo|guten (?:tag|morgen|abend)|buenos (?:días|dias)|buenas(?: tardes| noches)?)\\b[\\s!.,?¿¡]*\\p{L}*[\\s!.?]*$")

    /// Quoted words are what the question is about, not the language it's asked in: "Translate 'bom dia' to English" (validator C-3).
    private static let quoted = Rx("'[^'\\n]{1,80}'|\"[^\"\\n]{1,80}\"|\u{201C}[^\u{201D}\\n]{1,80}\u{201D}|\u{2018}[^\u{2019}\\n]{1,80}\u{2019}|«[^»\\n]{1,80}»")

    /// An English request about another language's words: "translate … to English", "how do you say …", "what does … mean".
    private static let enFrame = re("^\\s*(?:please\\s+)?(?:translate|how do (?:you|i) say|what does .{1,60} mean|what is the meaning of|meaning of)\\b")

    private static let word = Rx("\\p{L}+")
    /// Portuguese small words a title in English sits among: "Resumo de The Matrix".
    private static let ptSmall = re("(?<![\\p{L}])(de|do|da|dos|das|em|no|na|para|sobre|resumo|letra|significado|tradução)(?![\\p{L}])")
    private static let ptWords = re("(?<![\\p{L}])(não|é|são|está|você|como|qual|quais|quanto|quantos|porque|por que|uma|um|do|da|dos|das|no|na|nos|nas|em|para|com|isso|meu|minha|tem|têm|faz|fazer|posso|olá|oi|obrigado|obrigada)(?![\\p{L}])")

    private static func distinct(_ re: Rx, _ text: String) -> Int { Set(re.all(text).map { $0.value.lowercased() }).count }

    /// Kotlin `Regex.matches`: the whole text, not a part of it.
    private static func matchesWhole(_ re: Rx, _ text: String) -> Bool {
        guard let m = re.find(text) else { return false }
        return m.start == 0 && m.end == text.u16Count
    }

    /// The language `text` is clearly in, or nil when it can't be told (a few words, numbers, a name).
    public static func clear(_ text: String) -> Lang? {
        if enFrame.contains(text) { return .en }
        let replaced = quoted.replace(text, with: " ")
        let t = replaced.allSatisfy(\.isWhitespace) ? text : replaced
        if matchesWhole(greetingOther, t) || other(t) { return .other }
        if QueryContext.isPortugueseQuestion(t) || PtLexicon.looksPortuguese(t) { return .pt }
        // One English word beside Portuguese ones is a title ("Resumo de The Matrix", "Letra de Let It Be"): can't
        // tell, the conversation or the app decides (validator R-D1).
        if distinct(enWords, t) == 1 && ptSmall.contains(t) { return nil }
        return enWords.contains(t) ? .en : nil
    }

    /// Clearly Spanish, French or German: ¿ or ¡, or two of one language's own words and more of them than of
    /// Portuguese's or English's. Shared words ("de", "a", "que") don't count either way.
    private static func other(_ t: String) -> Bool {
        if QueryContext.isSpanishQuestion(t) { return true }
        let best = max(distinct(esWords, t), distinct(frWords, t), distinct(deWords, t))
        let pt = distinct(ptWords, t), en = distinct(enWords, t)
        // One marker word is enough in a sentence of three words or more with no Portuguese or English word at all
        // ("Wie viele Einwohner hat Berlin", "combien de temps dure un vol"; validator R-D5). A lone "gracias" stays
        // ambiguous.
        if best == 1 && pt == 0 && en == 0 && word.all(t).count >= 3 { return true }
        if best < 2 { return false }
        return best > pt && best > en
    }

    /// The phone's own language ("pt" for pt-BR); with a per-app language on iOS, that one.
    private static func phoneLanguage() -> String {
        let tag = current.phone ?? Locale.preferredLanguages.first ?? "en"
        return Locale(identifier: tag).language.languageCode?.identifier ?? tag
    }

    /// The phone's own language when the app follows the system: "System" is not English (validator C-2).
    public static func setting(_ app: String?) -> String { app ?? phoneLanguage() }

    /// `earlier`: the user's earlier turns, oldest first; the app's language as set.
    public static func of(_ question: String, earlier: [String] = []) -> Lang { of(question, earlier: earlier, app: appLanguage) }

    /// `app`: the app's language setting, nil when it follows the system.
    public static func of(_ question: String, earlier: [String], app: String?) -> Lang {
        if let l = clear(question) { return l }
        for e in earlier.reversed() { if let l = clear(e) { return l } }
        return setting(app) == "pt" ? .pt : .en
    }

    /// The line next to the question, or nil for English (its prompt stays as it was).
    public static func line(_ lang: Lang, withSources: Bool, filesOnly: Bool = false) -> String? {
        // Arm 0 (bench only): the app as it was, no line, for the "before" run.
        if lang != .pt || arm == 0 { return nil }
        return filesOnly && withSources ? ptFilesOnly : withSources ? ptWithSources : ptNoSources
    }
}
