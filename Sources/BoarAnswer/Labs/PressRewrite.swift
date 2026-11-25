import BoarRouting
import Foundation

/// Press's "Ask BOAR to rewrite it" (android engine `labs/PressRewrite.kt`, adam's mock-up, Nov 13): the prompt for each
/// option, in the text's language, the clean-up of what the model wrote (its reasoning out), and the check that the
/// answer's [n] source marks came back as they were. The app runs it on the loaded chat model and changes nothing until
/// the user picks "Use the new text". The receipt counts which sources a changed answer still cites with `marks`.
public enum PressRewrite {
    public enum Option: String, Sendable, CaseIterable {
        case shorter, simpler, fix, list, formal, paragraph, own
    }

    public struct Prompt: Sendable, Equatable {
        public let system: String
        public let user: String
        public let nPredict: Int
    }

    /// The text's language: Portuguese when it reads as Portuguese, else English.
    public static func portuguese(_ text: String) -> Bool { QueryContext.isPortugueseQuestion(text) }

    private static let systemEn = "You rewrite a passage for a document. Reply with the rewritten passage only: no preface, no title, no quotes, " +
        "no notes. Write in English, as the passage is. Keep every source mark such as [1] or [2] exactly as written, after the same " +
        "statement; do not add, drop or renumber any. Do not add facts that are not in the passage."
    private static let systemPt = "Você reescreve um trecho para um documento. Responda só com o trecho reescrito: sem introdução, sem título, " +
        "sem aspas, sem notas. Escreva em português, como o trecho. Mantenha cada marca de fonte como [1] ou [2] exatamente como está, " +
        "depois da mesma afirmação; não acrescente, não tire e não renumere nenhuma. Não acrescente fatos que não estejam no trecho."

    /// Kotlin `Regex("\\[(\\d{1,3})]")` (Java's `\d` is ASCII).
    private static let mark = try! NSRegularExpression(pattern: #"\[([0-9]{1,3})\]"#)
    /// Java's `\s`: ASCII whitespace only.
    private static let javaSpace = #"[ \t\n\x{0B}\f\r]+"#

    /// Words in `text`, [n] marks not counted (Kotlin `isLetterOrDigit`: a letter or a decimal digit).
    public static func words(_ text: String) -> Int {
        let ns = text as NSString
        let spaced = mark.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return spaced.replacingOccurrences(of: javaSpace, with: "\u{0}", options: .regularExpression)
            .split(separator: "\u{0}", omittingEmptySubsequences: false)
            .count { $0.unicodeScalars.contains(where: isLetterOrDigit) }
    }

    private static func isLetterOrDigit(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: true
        default: false
        }
    }

    /// "Shorter": at most half the words (and never under 8), a number the model can aim at (t9 1721: "about half" came
    /// back unchanged).
    public static func shorterTarget(_ text: String) -> Int { max(8, words(text) / 2) }

    /// Each quick action with a concrete target (t9 1721, after "Shorter" returned the same text on the F3): Shorter = at
    /// most half the words; Simpler words = short everyday words, the same facts; Fix the wording = the same length.
    public static func instruction(_ option: Option, own: String?, pt: Bool, text: String = "") -> String {
        switch option {
        case .shorter:
            let n = shorterTarget(text)
            return pt ? "Reescreva em no máximo \(n) palavras (hoje são \(words(text))). Fique só com os pontos principais e corte o resto."
                : "Rewrite it in at most \(n) words (it has \(words(text)) now). Keep only the main points and cut the rest."
        case .simpler:
            return pt ? "Reescreva com palavras curtas do dia a dia e frases curtas, como para uma criança de 10 anos. Os mesmos fatos, nenhum fato novo. Troque toda palavra difícil."
                : "Rewrite it with short, everyday words and short sentences, as for a 10-year-old. The same facts, no new ones. Replace every hard word."
        case .fix:
            let n = words(text)
            return pt ? "Corrija só a gramática, a ortografia e a redação. Mesmo tamanho (cerca de \(n) palavras) e os mesmos fatos."
                : "Fix only the grammar, spelling and wording. The same length (about \(n) words) and the same facts."
        case .list:
            return pt ? "Transforme em uma lista, um ponto por linha, cada linha começando com \"- \"." : "Turn it into a list, one point per line, each line starting with \"- \"."
        // adam, Nov 14: "2 more presets" (t9 0136 picked these): a report's tone at the same length, and the reverse of As a list.
        case .formal:
            let n = words(text)
            return pt ? "Reescreva em tom formal e neutro, como em um relatório: frases completas, sem gírias. Os mesmos fatos e mais ou menos o mesmo tamanho (cerca de \(n) palavras)."
                : "Rewrite it in a formal, neutral tone, as for a report: full sentences, no slang, no contractions. The same facts and about the same length (about \(n) words)."
        case .paragraph:
            return pt ? "Reescreva como um só parágrafo de frases completas: junte os pontos ou itens em texto corrido, sem marcadores e sem quebras de linha. Os mesmos fatos, nenhum fato novo."
                : "Rewrite it as one paragraph of full sentences: join the points or list items into running text, with no bullets and no line breaks. The same facts, no new ones."
        case .own:
            return (pt ? "Reescreva assim: " : "Rewrite it this way: ") + take((own ?? "").kotlinTrim(), 200)
        }
    }

    /// The user's own words (the note bar, or the sheet's field) may ask for new text, not a rewording: "replace this with
    /// something about the document" (adam on the F3, Nov 12: the model kept returning "this is a test"). So that option
    /// gets the rest of the document to read, and may write new text from it.
    private static let ownEn = "You edit one passage of a document, doing exactly what the writer's INSTRUCTION says. The instruction may ask " +
        "for new text in place of the passage: then write it, using the DOCUMENT to know what it is about. Reply with the new passage " +
        "only: no preface, no title, no quotes, no notes. Write in English. Use only facts from the document or the passage. Keep a " +
        "source mark such as [1] only if the passage already has it; never add a new one."
    private static let ownPt = "Você edita um trecho de um documento, fazendo exatamente o que a INSTRUÇÃO de quem escreve pede. A instrução pode " +
        "pedir um texto novo no lugar do trecho: então escreva, usando o DOCUMENTO para saber do que se trata. Responda só com o novo " +
        "trecho: sem introdução, sem título, sem aspas, sem notas. Escreva em português. Use só fatos do documento ou do trecho. " +
        "Mantenha uma marca de fonte como [1] só se o trecho já a tiver; nunca acrescente uma nova."

    /// The rest of the document for the model to read: its title and the other blocks' text, `max` characters at most.
    public static func documentContext(_ title: String, _ others: [String], max: Int = 1500) -> String {
        take(([title.kotlinTrim()] + others.map { $0.kotlinTrim() }).filter { !$0.isEmpty }.joined(separator: "\n\n"), max).kotlinTrim()
    }

    /// The model's prompt for `text` (the language from `languageOf`, the text by default). Room to write: about the
    /// text's length again, more for a list, between 96 and 1024 tokens; the user's own words get room for new text.
    public static func prompt(_ option: Option, _ text: String, own: String? = nil, languageOf: String? = nil, document: String = "") -> Prompt {
        let pt = portuguese(languageOf ?? text)
        let length = text.utf16.count
        if option == .own {
            let d = document.kotlinTrim()
            let doc = d.isEmpty ? "" : (pt ? "DOCUMENTO (só para contexto, não copie):" : "DOCUMENT (for context only, do not copy it):") + "\n" + d + "\n\n"
            let user = doc + (pt ? "TRECHO:" : "PASSAGE:") + "\n" + text.kotlinTrim() + "\n\n" + (pt ? "INSTRUÇÃO: " : "INSTRUCTION: ") + take((own ?? "").kotlinTrim(), 200)
            // Room for new text, not only the passage's length again.
            return Prompt(system: pt ? ownPt : ownEn, user: user, nPredict: min(max(length / 3 * 3 / 2 + 64, 320), 1024))
        }
        // The passage first, the task last: small models copied the passage back when the task came first (the F3, Nov
        // 12: "Shorter" returned the same text on Qwen3 1.7B).
        let user = (pt ? "TRECHO:" : "PASSAGE:") + "\n" + text.kotlinTrim() + "\n\n" + (pt ? "TAREFA: " : "TASK: ") + instruction(option, own: own, pt: pt, text: text)
        let tokens = length / 3
        let n = switch option {
        case .shorter: tokens
        case .list: tokens * 2
        default: tokens * 3 / 2
        }
        return Prompt(system: pt ? systemPt : systemEn, user: user, nPredict: min(max(n + 64, 96), 1024))
    }

    /// What has been written so far, for the screen: the reasoning (while it lasts) hidden.
    public static func visible(_ raw: String) -> String { AnswerText.splitThinking(raw).answer.kotlinTrim() }

    private static let label = try! NSRegularExpression(
        pattern: #"^(rewritten( passage| text)?|passage|texto reescrito|trecho( reescrito)?|reescrito)[ \t\n\x{0B}\f\r]*:[ \t\n\x{0B}\f\r]*"#,
        options: [.caseInsensitive])

    /// The rewrite as it goes in the block: no reasoning, no "Rewritten:" label, no quotes around it all.
    public static func clean(_ raw: String) -> String {
        var s = AnswerText.stripThinking(raw).kotlinTrim()
        s = label.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "").kotlinTrim()
        if let f = s.first, let l = s.last, s.count >= 2, (f == "\"" && l == "\"") || (f == "“" && l == "”") {
            s = String(s.dropFirst().dropLast()).kotlinTrim()
        }
        return s
    }

    /// The rewrite says the same as the text (spaces and case aside): the screen says "No change" instead of NOW /
    /// REWRITTEN.
    public static func unchanged(_ before: String, _ after: String) -> Bool {
        func norm(_ x: String) -> String { x.kotlinTrim().replacingOccurrences(of: javaSpace, with: " ", options: .regularExpression).lowercased() }
        return norm(before) == norm(after)
    }

    /// What became of a rewrite (android `PressRewriter.Outcome`, the part decided from the text).
    public enum Outcome: Sendable, Equatable {
        /// Nothing usable came back.
        case failed
        /// The model gave the text back as it was: "No change", not NOW / REWRITTEN twice the same (t9 1721).
        case unchanged
        case done(text: String, marksChanged: Bool)
    }

    /// The model's reply `raw` for `text`: cleaned, and never a source mark the passage didn't have, whatever the option
    /// (validator G-2).
    public static func outcome(_ text: String, raw: String) -> Outcome {
        let out = dropNewMarks(text, clean(raw))
        if out.allSatisfy(\.isWhitespace) { return .failed }
        if unchanged(text, out) { return .unchanged }
        return .done(text: out, marksChanged: marksChanged(text, out))
    }

    /// Kotlin `take(n)`: the first `n` UTF-16 units; a surrogate pair cut in half loses its lone first half, which a Swift
    /// string can't hold.
    static func take(_ s: String, _ n: Int) -> String {
        guard s.utf16.count > n else { return s }
        var u = Array(s.utf16.prefix(n))
        if let last = u.last, UTF16.isLeadSurrogate(last) { u.removeLast() }
        return String(decoding: u, as: UTF16.self)
    }

    /// A source mark in any shape a model writes (validator G-2): [5], [ 5 ], [1, 5], [1-5], [5;6], [S5], [^5], 【5】.
    /// Up to three letters may stand before a number; three digits at most, so a year in brackets is not a mark.
    /// (Java's `\s` and `\d` are ASCII: spelled out.)
    static let anyMark = try! NSRegularExpression(pattern:
        #"[\[【][ \t\n\x{0B}\f\r]*\^?[A-Za-z]{0,3}[ \t\n\x{0B}\f\r]*[0-9]{1,3}(?:[ \t\n\x{0B}\f\r]*[-–,;][ \t\n\x{0B}\f\r]*\^?[A-Za-z]{0,3}[ \t\n\x{0B}\f\r]*[0-9]{1,3})*[ \t\n\x{0B}\f\r]*[\]】]"#)
    private static let digits = try! NSRegularExpression(pattern: "[0-9]{1,3}")
    private static let dash = try! NSRegularExpression(pattern: "[-–]")

    /// The numbers one mark stands for: a range 1-5 is every number in it (at most 50).
    static func numbersIn(_ mark: String) -> [Int] {
        let trimSet: Set<Character> = ["[", "]", "【", "】", " "]
        var body = Substring(mark)
        while let f = body.first, trimSet.contains(f) { body.removeFirst() }
        while let l = body.last, trimSet.contains(l) { body.removeLast() }
        var out: [Int] = []
        for part in body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == ";" }).map(String.init) {
            let ns = part as NSString
            let n = digits.matches(in: part, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range)) }
            let hasDash = dash.firstMatch(in: part, range: NSRange(location: 0, length: ns.length)) != nil
            if n.count == 2 && hasDash && n[1] >= n[0] && n[1] - n[0] < 50 { out += Array(n[0]...n[1]) } else { out += n }
        }
        return out
    }

    /// The source marks in a text, each once, whatever their shape.
    public static func marks(_ text: String) -> Set<Int> {
        let ns = text as NSString
        return Set(anyMark.matches(in: text, range: NSRange(location: 0, length: ns.length)).flatMap { numbersIn(ns.substring(with: $0.range)) })
    }

    /// New text written from the user's own words must not cite what the passage didn't: a [n] that wasn't there before
    /// is taken out. Marks the passage had stay, written back plainly: [1, 5] with only 1 known becomes [1].
    public static func dropNewMarks(_ before: String, _ after: String) -> String {
        let had = marks(before)
        let kept = PressText.replace(anyMark, in: after) { m in
            var seen = Set<Int>()
            return numbersIn(m).filter { seen.insert($0).inserted && had.contains($0) }.map { "[\($0)]" }.joined()
        }
        return kept.replacingOccurrences(of: #" +([.,;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression).kotlinTrim()
    }

    /// A mark that was there is missing, or a new one appeared: the screen says "Some source marks changed".
    public static func marksChanged(_ before: String, _ after: String) -> Bool { marks(before) != marks(after) }
}

/// Small regex helpers the Press files share.
enum PressText {
    /// Kotlin `Regex.replace(input) { transform }`: each match's text through `f`.
    static func replace(_ re: NSRegularExpression, in s: String, _ f: (String) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    /// Kotlin `Regex.replace(input) { transform }` with the match's groups.
    static func replaceGroups(_ re: NSRegularExpression, in s: String, _ f: ([String?]) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { i -> String? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            out += f(groups)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}
