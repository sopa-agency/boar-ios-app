import Foundation

/// Boar Polyglot's decision, pure (android `routing/LanguageGate.kt`): is this question clearly a full sentence in a
/// language BOAR doesn't answer in? Then the app replies at once ("Sorry, BOAR doesn't speak Russian yet.") instead of
/// running the model on it. It blocks only when every check agrees, and passes everything it isn't sure about:
/// 1. what is left after cleaning (URLs, emails, numbers, code, emoji, quoted text, capitalized names) is long enough:
///    `minWords` words, or `minCharsNoSpace` letters in a script written without spaces;
/// 2. the message has no English or Portuguese function words ("What does 'je ne sais quoi' mean?" passes);
/// 3. it isn't a greeting, a thanks, ok, yes or no in any of about 25 languages;
/// 4. the language is sure: a non-Latin script by its letters (`scriptShare` of them in one script), a Latin one by the
///    device's detector (confidence `minConfidence`, `minMargin` ahead of the next). No detector: Latin text passes.
/// A short follow-up (`followUpWords` words) in a chat whose last question was answered passes too.
/// The detector is the app's (NaturalLanguage on iOS, TextClassifier on Android); it is passed in so this stays testable.
///
/// Indexes are UTF-16 where Kotlin walks `Char`s (quotes, function words) and Unicode scalars where it walks code points
/// (tokens, letters, scripts). A letter's script comes from ICU's Script property through `NSRegularExpression`; a script
/// with no language here counts as one "other" script (Kotlin keeps each apart), which only matters for text mixing two
/// such scripts, and that text passes either way.
public enum LanguageGate {
    /// The receipt's tool code for this reply.
    public static let tool = "language"

    /// Languages BOAR answers in. Spanish is allowed for now; take it out here to reply to it too.
    public static let allowed: Set<String> = ["en", "pt", "es"]

    public static let minWords = 4
    public static let minCharsNoSpace = 8
    public static let minScriptLetters = 6
    public static let scriptShare = 0.70
    public static let minConfidence: Float = 0.90
    public static let minMargin: Float = 0.25
    public static let followUpWords = 6

    /// Only this much of a long message is measured; the function-word check reads all of it.
    private static let maxScan = 4_000

    /// A quoted span longer than this isn't a quote (an unmatched mark); the mark is kept as punctuation.
    private static let maxQuote = 300

    public enum Decision: Sendable, Equatable {
        case allowed
        /// ISO 639-1 code ("ru", "fr", "zh").
        case unsupported(String)
    }

    /// The device's guesses for the cleaned text, best first (code and confidence).
    public typealias Guesses = [(String, Float)]

    /// `detected`: the detector's guesses for the cleaned text; nil when there is no detector.
    public static func decide(_ text: String, _ detected: Guesses?, followUp: Bool = false) -> Decision {
        decide(text, followUp: followUp) { _ in detected }
    }

    /// As `decide(_:_:followUp:)`, calling `detect` (with the cleaned text) only when the answer depends on it.
    public static func decide(_ text: String, followUp: Bool, detect: (String) throws -> Guesses?) -> Decision {
        if isBlank(text) { return .allowed }
        if hasEnglishOrPortuguese(text) { return .allowed }
        if allowed.contains("es") && QueryContext.isSpanishQuestion(text) { return .allowed }
        let cleaned = clean(text)
        let words = cleaned.unicodeScalars.split(separator: " ", omittingEmptySubsequences: true).map { String(String.UnicodeScalarView($0)) }
        if words.isEmpty || isSkip(words) { return .allowed }
        let stats = scriptStats(cleaned)
        let noSpace = stats.dominant.map { noSpaceScripts.contains($0) } ?? false
        if followUp {
            let size = noSpace ? (stats.letters + 1) / 2 : splitJavaWhitespace(kotlinTrim(text)).count
            if size <= followUpWords { return .allowed }
        }
        let long = words.count >= minWords || (noSpace && stats.dominantLetters >= minCharsNoSpace)
        guard long, let dominant = stats.dominant else { return .allowed }
        if dominant == "Latin" {
            guard let raw = try? detect(cleaned) else { return .allowed }
            let guesses = sortedDescending(raw.map { (normalize($0.0), $0.1) })
            guard let top = guesses.first else { return .allowed }
            let second = guesses.count > 1 ? guesses[1].1 : 0
            if top.0.isEmpty || top.0 == "und" || allowed.contains(top.0) { return .allowed }
            if top.1 < minConfidence || top.1 - second < minMargin { return .allowed }
            return .unsupported(top.0)
        }
        if stats.dominantLetters < minScriptLetters { return .allowed }
        guard let language = scriptLanguage(stats, cleaned, { try? detect(cleaned) }) else { return .allowed }
        return allowed.contains(language) ? .allowed : .unsupported(language)
    }

    // MARK: Java and Kotlin character semantics

    /// Java `Character.isLetter`: general category L*.
    static func isLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool { s.properties.generalCategory == .decimalNumber }

    /// Kotlin `Char.isLetterOrDigit` on one UTF-16 unit (a surrogate half is neither).
    private static func isLetterOrDigit(unit u: UInt16) -> Bool {
        guard let s = Unicode.Scalar(u) else { return false }
        return isLetter(s) || isDigit(s)
    }

    /// Kotlin `String.contains`: by UTF-16 units, not by grapheme.
    private static func has(_ s: String, _ sub: String) -> Bool { (s as NSString).range(of: sub, options: .literal).location != NSNotFound }

    /// Kotlin `Char.isWhitespace`: Java whitespace or a space separator.
    private static func isKotlinWhitespace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x1F: return true
        default:
            let c = s.properties.generalCategory
            return c == .spaceSeparator || c == .lineSeparator || c == .paragraphSeparator
        }
    }

    private static func isBlank(_ s: String) -> Bool { s.unicodeScalars.allSatisfy(isKotlinWhitespace) }

    private static func kotlinTrim(_ s: String) -> String {
        var v = Substring(s).unicodeScalars
        while let f = v.first, isKotlinWhitespace(f) { v.removeFirst() }
        while let l = v.last, isKotlinWhitespace(l) { v.removeLast() }
        return String(v)
    }

    /// Java's `\s` without UNICODE_CHARACTER_CLASS: ASCII only.
    private static func isJavaSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: true
        default: false
        }
    }

    /// Kotlin `s.split(Regex("\\s+"))`: pieces between runs of ASCII whitespace, empty ones kept.
    private static func splitJavaWhitespace(_ s: String) -> [String] {
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        var inRun = false
        for c in s.unicodeScalars {
            if isJavaSpace(c) {
                if !inRun { out.append(String(cur)); cur = String.UnicodeScalarView(); inRun = true }
            } else {
                inRun = false
                cur.append(c)
            }
        }
        out.append(String(cur))
        return out
    }

    /// Kotlin `sortedByDescending { it.second }` on Floats: stable, NaN above everything (Float.compareTo).
    private static func greater(_ a: Float, _ b: Float) -> Bool {
        if a.isNaN { return !b.isNaN }
        if b.isNaN { return false }
        return a > b
    }

    private static func sortedDescending(_ g: Guesses) -> Guesses {
        g.enumerated().sorted { x, y in
            if greater(x.element.1, y.element.1) { return true }
            if greater(y.element.1, x.element.1) { return false }
            return x.offset < y.offset
        }.map(\.element)
    }

    // MARK: cleaning

    /// Lowercase-free: the words left to measure, separated by single spaces.
    public static func clean(_ text: String) -> String {
        let ns = text as NSString
        let src = ns.length > maxScan ? ns.substring(to: maxScan) : text
        let noCode = dropCodeLines(dropBackticks(src))
        let noQuotes = dropQuotes(noCode)
        var out = ""
        for line in JsString.split(noQuotes, "\n") {
            var sentenceStart = true
            for raw in splitJavaWhitespace(line) where !raw.isEmpty {
                let ends = endsSentence(raw)
                if keepToken(raw, sentenceStart: sentenceStart) {
                    let word = lettersOnly(raw)
                    if !word.isEmpty { out += word + " " }
                }
                sentenceStart = ends
            }
        }
        return multiSpace.replace(in: kotlinTrim(out), with: " ")
    }

    private static let multiSpace = JsRegex(" {2,}")

    /// Text between backticks (`x`, ```block```) is code; an unmatched last backtick is kept as it is.
    private static func dropBackticks(_ s: String) -> String {
        if !has(s, "`") { return s }
        let parts = JsString.split(s, "`")
        var sb = ""
        for i in parts.indices where i % 2 == 0 || (i == parts.count - 1 && parts.count % 2 == 0) {
            sb += parts[i] + " "
        }
        return sb
    }

    /// A line with braces, or a semicolon beside code marks (=, brackets, $), is code. A lone ';' is Greek's question mark.
    private static func dropCodeLines(_ s: String) -> String {
        if !has(s, "{") && !has(s, "}") && !has(s, ";") { return s }
        return JsString.split(s, "\n").filter { line in
            !(has(line, "{") || has(line, "}") || (has(line, ";") && line.unicodeScalars.contains(where: { "=()[]<>$".unicodeScalars.contains($0) })))
        }.joined(separator: "\n")
    }

    private static let quotePairs: [UInt16: [UInt16]] = {
        let pairs: [(Character, String)] = [("«", "»"), ("»", "«"), ("“", "”„"), ("„", "“”"), ("\"", "\""), ("‘", "’"), ("‚", "‘’"), ("「", "」"), ("『", "』"), ("'", "'")]
        var m: [UInt16: [UInt16]] = [:]
        for (open, close) in pairs { m[open.utf16.first!] = Array(close.utf16) }
        return m
    }()
    private static let straightQuote = Character("'").utf16.first!
    private static let newline: UInt16 = 0x0A

    /// Removes quoted spans. A straight ' quotes only from outside a word to outside a word (don't, l'eau stay).
    private static func dropQuotes(_ s: String) -> String {
        let u = Array(s.utf16)
        if !u.contains(where: { quotePairs[$0] != nil }) { return s }
        let finder = Closers(u)
        var out: [UInt16] = []
        out.reserveCapacity(u.count)
        var i = 0
        while i < u.count {
            let c = u[i]
            if let closers = quotePairs[c], c != straightQuote || i == 0 || !isLetterOrDigit(unit: u[i - 1]) {
                let end = finder.find(i + 1, closers, straight: c == straightQuote)
                if end >= 0 {
                    out.append(0x20)
                    i = end + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// Kotlin's findCloser (the first closer within `maxQuote` units and before a newline; a straight ' only before a
    /// non-letter) over next-occurrence tables, so a run of unmatched marks costs one step each, not `maxQuote`.
    private struct Closers {
        let u: [UInt16]
        /// next[c][j]: the first index >= j holding c (u.count when none); nextLine likewise for "\n".
        private var next: [UInt16: [Int]] = [:]
        private let nextLine: [Int]

        init(_ u: [UInt16]) {
            self.u = u
            nextLine = Closers.table(u, newline)
            for c in Set(quotePairs.values.joined()) where u.contains(c) { next[c] = Closers.table(u, c) }
        }

        private static func table(_ u: [UInt16], _ c: UInt16) -> [Int] {
            var t = [Int](repeating: u.count, count: u.count + 1)
            var j = u.count - 1
            while j >= 0 { t[j] = u[j] == c ? j : t[j + 1]; j -= 1 }
            return t
        }

        func find(_ from: Int, _ closers: [UInt16], straight: Bool) -> Int {
            if from >= u.count { return -1 }
            let stop = min(u.count, from + maxQuote, nextLine[from])
            if !straight {
                let j = closers.compactMap { next[$0]?[from] }.min() ?? u.count
                return j < stop ? j : -1
            }
            guard let t = next[straightQuote] else { return -1 }
            var j = t[from]
            while j < stop {
                if j + 1 >= u.count || !isLetterOrDigit(unit: u[j + 1]) { return j }
                j = t[j + 1]
            }
            return -1
        }
    }

    private static let closingMarks = Set("\"'”’»)]」』".unicodeScalars)
    private static let sentenceEnds = Set(".!?…:;。！？".unicodeScalars)

    private static func endsSentence(_ token: String) -> Bool {
        var v = Substring(token).unicodeScalars
        while let l = v.last, closingMarks.contains(l) { v.removeLast() }
        return v.last.map { sentenceEnds.contains($0) } ?? false
    }

    /// Drops URLs, emails, anything with a digit, and a capitalized word that doesn't start a sentence (a name, a place).
    private static func keepToken(_ token: String, sentenceStart: Bool) -> Bool {
        if has(token, "://") || (token as NSString).range(of: "www.", options: [.anchored, .caseInsensitive, .literal]).location != NSNotFound { return false }
        let ns = token as NSString
        let at = ns.range(of: "@").location
        if at != NSNotFound && at > 0 {
            let dot = ns.range(of: ".", options: .literal, range: NSRange(location: at, length: ns.length - at)).location
            if dot != NSNotFound && dot > at { return false }
        }
        var firstLetter: Unicode.Scalar?
        for cp in token.unicodeScalars {
            if isDigit(cp) { return false }
            if firstLetter == nil && isLetter(cp) { firstLetter = cp }
        }
        guard let first = firstLetter else { return false }
        return sentenceStart || !(first.properties.isUppercase || first.properties.generalCategory == .titlecaseLetter)
    }

    /// Letters and combining marks; an apostrophe or hyphen inside a word is kept; emoji and punctuation go.
    private static func lettersOnly(_ token: String) -> String {
        let cps = Array(token.unicodeScalars)
        var sb = String.UnicodeScalarView()
        for (i, cp) in cps.enumerated() {
            let type = cp.properties.generalCategory
            if isLetter(cp) || type == .nonspacingMark || type == .spacingMark {
                sb.append(cp)
            } else if (cp == "'" || cp == "’" || cp == "-") && !sb.isEmpty && i + 1 < cps.count && isLetter(cps[i + 1]) {
                sb.append(cp)
            } else if let last = sb.last, last != " " {
                sb.append(" ")
            }
        }
        return kotlinTrim(String(sb))
    }

    // MARK: function words and skip list

    /// English and Portuguese words one of them is enough for.
    private static let strong: Set<String> = [
        "the", "what", "what's", "whats", "how", "how's", "why", "where", "where's", "which", "who", "whom", "whose", "when",
        "does", "doesn't", "did", "didn't", "isn't", "aren't", "can't", "don't", "mean", "means", "meaning", "meant", "say",
        "said", "words", "english", "portuguese", "please", "you", "your", "this", "that", "these", "those", "it",
        "it's", "its", "would", "could", "should", "have", "there", "they", "i'm", "and", "with", "about", "from",
        "como", "qual", "quais", "é", "são", "onde", "porque", "porquê", "você", "vocês", "não", "isso", "isto", "significa",
        "significado", "quem", "português", "portugues", "inglês", "ingles", "palavra", "tradução", "traducao",
    ]

    /// Shared with other languages (Dutch "is", Polish "do", Turkish "can", Romanian "are"): two different ones are needed.
    private static let weak: Set<String> = ["is", "do", "can", "are"]

    private static let strongPairs: Set<String> = ["o que", "por que", "quer dizer", "o quê"]

    /// Any English or Portuguese function word: the message is in an allowed language, maybe quoting another one.
    public static func hasEnglishOrPortuguese(_ text: String) -> Bool {
        var tokens: [String] = []
        var sb: [UInt16] = []
        func flush() {
            if !sb.isEmpty { tokens.append(String(decoding: sb, as: UTF16.self).lowercased()); sb.removeAll() }
        }
        let apostrophe: UInt16 = 0x27, curly: UInt16 = 0x2019
        for c in text.utf16 {
            let letter = Unicode.Scalar(c).map(isLetter) ?? false
            if letter || ((c == apostrophe || c == curly) && !sb.isEmpty) { sb.append(c == curly ? apostrophe : c) } else { flush() }
        }
        flush()
        var weakSeen: String?
        for (i, t) in tokens.enumerated() {
            var w = Substring(t)
            while w.last == "'" { w.removeLast() }
            let word = String(w)
            if strong.contains(word) || word.hasPrefix("translat") || word.hasPrefix("traduz") || word.hasPrefix("traduç") { return true }
            if i > 0 && strongPairs.contains("\(tokens[i - 1]) \(word)") { return true }
            if weak.contains(word) {
                if let seen = weakSeen, seen != word { return true }
                weakSeen = word
            }
        }
        return false
    }

    private static let skipWords: Set<String> = [
        // English, Portuguese, Spanish
        "ok", "okay", "okey", "k", "kk", "yes", "yeah", "yep", "no", "nope", "hi", "hello", "hey", "bye", "goodbye", "thanks",
        "thank", "thx", "ty", "good", "morning", "night", "evening", "afternoon", "very", "much", "so", "lot", "sim", "não",
        "nao", "olá", "ola", "oi", "tchau", "obrigado", "obrigada", "valeu", "bom", "dia", "boa", "noite", "tarde", "muito",
        "gracias", "hola", "adiós", "adios", "sí", "si", "buenos", "días", "buenas", "noches", "mucho", "muchas",
        // French, German, Italian, Dutch
        "merci", "beaucoup", "bonjour", "bonsoir", "salut", "oui", "non", "au", "revoir", "très", "bien", "d'accord",
        "danke", "schön", "schon", "sehr", "vielen", "dank", "ja", "nein", "hallo", "tschüss", "guten", "morgen", "tag",
        "abend", "gut", "grazie", "mille", "ciao", "buongiorno", "buonasera", "prego", "sì", "molto", "bene", "dankjewel",
        "bedankt", "dankje", "goedemorgen", "doei", "nee",
        // Nordic, Polish, Czech, Hungarian, Romanian, Turkish, Indonesian, Swahili, Finnish
        "tak", "tack", "takk", "hej", "hei", "kiitos", "dzięki", "dziękuję", "cześć", "dobry", "dzień", "děkuji", "ahoj",
        "köszönöm", "szia", "mulțumesc", "multumesc", "merhaba", "teşekkürler", "teşekkür", "ederim", "sağol", "evet",
        "hayır", "terima", "kasih", "halo", "asante", "sana", "jambo",
        // Romanized
        "arigato", "arigatou", "xiexie", "xièxie", "nihao", "shukran", "salam", "toda", "spasibo", "efharisto", "namaste",
        "dhanyavaad", "gamsahamnida", "kamsahamnida", "annyeong", "konnichiwa", "aloha", "mahalo", "hvala",
        // Russian, Ukrainian, Greek, Arabic, Hebrew, Hindi, Thai
        "спасибо", "большое", "привет", "пока", "да", "нет", "здравствуйте", "доброе", "утро", "добрый", "день", "вечер",
        "дякую", "привіт", "так", "ні", "ευχαριστώ", "πολύ", "γεια", "σας", "ναι", "όχι", "شكرا", "شكرًا", "شكراً", "مرحبا",
        "نعم", "لا", "سلام", "תודה", "רבה", "שלום", "כן", "לא", "धन्यवाद", "नमस्ते", "शुक्रिया", "हाँ", "हां", "नहीं", "ขอบคุณ",
        "สวัสดี", "ครับ", "ค่ะ",
    ]

    /// Greetings and thanks in scripts written without spaces, letters only.
    private static let skipPhrases: Set<String> = [
        "谢谢", "謝謝", "多谢", "你好", "您好", "再见", "再見", "好的", "是", "不是", "对", "不", "谢谢你", "非常感谢",
        "ありがとう", "ありがとうございます", "ありがとうございました", "どうもありがとう", "こんにちは", "こんばんは", "おはよう",
        "おはようございます", "さようなら", "はい", "いいえ", "どうも",
        "감사합니다", "고맙습니다", "안녕하세요", "안녕", "네", "아니요", "아니오", "예",
        "ขอบคุณครับ", "ขอบคุณค่ะ", "ขอบคุณ", "สวัสดีครับ", "สวัสดีค่ะ", "สวัสดี", "ขอบคุณมากครับ", "ขอบคุณมากค่ะ",
    ]

    /// Set membership by Unicode scalars: Swift's String equality is canonical (NFC = NFD), Kotlin's is by UTF-16 units.
    private static let skipWordsExact = Set(skipWords.map { Array($0.unicodeScalars) })
    private static let skipPhrasesExact = Set(skipPhrases.map { Array($0.unicodeScalars) })
    private static func inSkipWords(_ s: String) -> Bool { skipWordsExact.contains(Array(s.unicodeScalars)) }
    private static func inSkipPhrases(_ s: String) -> Bool { skipPhrasesExact.contains(Array(s.unicodeScalars)) }

    /// All of it is a greeting, a thanks, yes or no; or half of it is and it starts with one ("merci beaucoup mon ami").
    private static func isSkip(_ words: [String]) -> Bool {
        let lower = words.map { $0.lowercased() }
        if inSkipPhrases(lower.joined()) { return true }
        let hits = lower.filter { inSkipWords($0) || inSkipPhrases($0) }.count
        return hits == lower.count || (inSkipWords(lower[0]) && hits * 2 >= lower.count)
    }

    // MARK: scripts

    /// ICU script names; a letter in none of them counts as "Other".
    private static let scriptNames = [
        "Latin", "Cyrillic", "Arabic", "Hebrew", "Greek", "Devanagari", "Bengali", "Gurmukhi", "Gujarati", "Oriya", "Tamil",
        "Telugu", "Kannada", "Malayalam", "Sinhala", "Thai", "Lao", "Khmer", "Myanmar", "Tibetan", "Georgian", "Armenian",
        "Ethiopic", "Han", "Hiragana", "Katakana", "Hangul", "Common", "Inherited",
    ]
    private static let scriptRe: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: scriptNames.map { "(\\p{Script=\($0)}+)" }.joined(separator: "|"))
    }()

    private static let noSpaceScripts: Set<String> = ["Han", "Hiragana", "Katakana", "Hangul", "Thai", "Lao", "Khmer", "Myanmar"]

    public struct ScriptStats: Sendable, Equatable {
        public let letters: Int
        /// An ICU script name ("Cyrillic", "Han"); Japanese is "Hiragana".
        public let dominant: String?
        public let dominantLetters: Int
        public let kana: Int
        public let han: Int
    }

    /// Han, Hiragana and Katakana count as one script (Japanese mixes them); `dominant` is nil under `scriptShare`.
    public static func scriptStats(_ s: String) -> ScriptStats {
        // Each distinct letter's script, from one regex pass over the distinct letters in code point order: scripts sit in
        // blocks, so that string is a few long runs of one script and the 29-way alternation runs a few times, not per letter.
        let distinct = Set(s.unicodeScalars.filter(isLetter)).sorted { $0.value < $1.value }
        var scriptOf: [Unicode.Scalar: Int] = [:]
        if !distinct.isEmpty {
            var view = String.UnicodeScalarView()
            var offsets: [Int] = []
            var at = 0
            for c in distinct { view.append(c); offsets.append(at); at += c.utf16.count }
            let joined = String(view)
            for m in scriptRe.matches(in: joined, range: NSRange(location: 0, length: at)) {
                guard let g = (1..<m.numberOfRanges).first(where: { m.range(at: $0).location != NSNotFound }) else { continue }
                let lo = m.range.location, hi = lo + m.range.length
                var k = offsets.firstIndex { $0 >= lo } ?? offsets.count
                while k < offsets.count && offsets[k] < hi { scriptOf[distinct[k]] = g - 1; k += 1 }
            }
        }
        var counts: [String: Int] = [:]
        var order: [String] = []
        var letters = 0, kana = 0, han = 0
        for cp in s.unicodeScalars {
            if !isLetter(cp) { continue }
            letters += 1
            var script = scriptOf[cp].map { scriptNames[$0] } ?? "Other"
            switch script {
            case "Hiragana", "Katakana": kana += 1; script = "Han"
            case "Han": han += 1
            default: break
            }
            if counts[script] == nil { order.append(script) }
            counts[script, default: 0] += 1
        }
        var best: (String, Int)?
        for k in order where best == nil || counts[k]! > best!.1 { best = (k, counts[k]!) }
        guard let best, letters > 0, Double(best.1) >= Double(letters) * scriptShare else {
            return ScriptStats(letters: letters, dominant: nil, dominantLetters: best?.1 ?? 0, kana: kana, han: han)
        }
        let dominant = best.0 == "Han" && kana > 0 ? "Hiragana" : best.0
        return ScriptStats(letters: letters, dominant: dominant, dominantLetters: best.1, kana: kana, han: han)
    }

    /// The languages each script is written in, the most spoken first (the answer when the detector can't tell).
    private static let scriptLanguages: [String: [String]] = [
        "Cyrillic": ["ru", "uk", "bg", "sr", "mk", "be", "kk", "ky", "mn", "tg", "tt", "ba", "cv"],
        "Arabic": ["ar", "fa", "ur", "ps", "ku", "sd", "ug", "ckb"],
        "Hebrew": ["he", "yi"],
        "Greek": ["el"],
        "Devanagari": ["hi", "mr", "ne", "sa"],
        "Bengali": ["bn", "as"],
        "Gurmukhi": ["pa"],
        "Gujarati": ["gu"],
        "Oriya": ["or"],
        "Tamil": ["ta"],
        "Telugu": ["te"],
        "Kannada": ["kn"],
        "Malayalam": ["ml"],
        "Sinhala": ["si"],
        "Thai": ["th"],
        "Lao": ["lo"],
        "Khmer": ["km"],
        "Myanmar": ["my"],
        "Tibetan": ["bo"],
        "Georgian": ["ka"],
        "Armenian": ["hy"],
        "Ethiopic": ["am", "ti"],
        "Han": ["zh"],
        "Hiragana": ["ja"],
        "Hangul": ["ko"],
    ]

    /// The detector's pick when it names a language of this script, else the letters' own clues, else the script's main language.
    private static func scriptLanguage(_ stats: ScriptStats, _ cleaned: String, _ detect: () -> Guesses?) -> String? {
        guard let dominant = stats.dominant, let options = scriptLanguages[dominant] else { return nil }
        if options.count > 1, let guesses = detect() {
            // Kotlin maxByOrNull: the first of the highest (NaN highest).
            var top: (String, Float)?
            for g in guesses.map({ (normalize($0.0), $0.1) }) where top == nil || greater(g.1, top!.1) { top = g }
            if let top, top.1 >= 0.5, options.contains(top.0) { return top.0 }
        }
        if dominant == "Cyrillic" {
            let has = { (set: String) in cleaned.unicodeScalars.contains { set.unicodeScalars.contains($0) } }
            if has("їєґЇЄҐ") || (has("іІ") && !has("ыэъЫЭЪ")) { return "uk" }
            if has("ўЎ") { return "be" }
        }
        return options.first
    }

    /// "zh-Hant" → "zh", "iw" → "he", "in" → "id"; lowercase.
    public static func normalize(_ code: String) -> String {
        let base = (code.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?.lowercased() ?? ""
        switch base {
        case "iw": return "he"
        case "in": return "id"
        case "ji": return "yi"
        case "jw": return "jv"
        default: return base
        }
    }
}
