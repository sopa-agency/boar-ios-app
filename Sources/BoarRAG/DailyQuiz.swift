import BoarCore
import Foundation

/// Boar Labs' Daily Quiz (android engine/vault `DailyQuiz.kt`, Oct 24): a few questions a day from BOAR's own library,
/// offline and without the model. Each shows an article's opening sentence with the title's words hidden, and four
/// titles to pick from. The date picks the questions (KotlinRandom, so an Android phone and an iPhone with the same
/// library get the same quiz), and the same day gives the same quiz on every open. On Android right answers also unlock
/// Boar Avatars (Vault); the iOS app has no Vault yet.
public enum DailyQuiz {
    public struct Question: Sendable, Equatable {
        public let clue: String
        public let options: [String]
        public let answer: Int
    }

    public static let mask = "▢▢▢"
    private static let minClue = 40
    private static let maxClue = 260

    private static let marks = try! NSRegularExpression(pattern: #"\p{M}+"#)
    private static let word = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
    /// Java's \s and \d are ASCII.
    private static let sentenceEnd = try! NSRegularExpression(pattern: #"(?<=[.!?])[ \t\n\x0B\f\r]+(?=[\p{Lu}0-9"“(])"#)
    private static let spaces = try! NSRegularExpression(pattern: #"[ \t\n\x0B\f\r]+"#)

    private static func replace(_ re: NSRegularExpression, _ s: String, _ with: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: s.utf16.count), withTemplate: NSRegularExpression.escapedTemplate(for: with))
    }

    private static func fold(_ s: String) -> String { replace(marks, s.lowercased().decomposedStringWithCanonicalMapping, "") }
    private static func stem(_ w: String) -> String { w.utf16.count > 3 && w.hasSuffix("s") ? String(w.dropLast()) : w }

    /// Kotlin `substringBefore`: the whole string when the delimiter isn't there.
    private static func before(_ s: String, _ delimiter: String) -> String {
        let r = (s as NSString).range(of: delimiter, options: .literal)
        return r.location == NSNotFound ? s : (s as NSString).substring(to: r.location)
    }

    private static func words(_ s: String) -> [String] {
        let ns = s as NSString
        return word.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// The title's words a clue must not show: three letters or more ("of", "a" stay).
    private static func titleWords(_ title: String) -> Set<String> {
        Set(words(fold(before(title, " ("))).map(stem).filter { $0.utf16.count >= 3 })
    }

    /// `sentence` with every word of `title` (any case, accent or plural) replaced by the mask.
    public static func mask(_ sentence: String, title: String) -> String {
        let hidden = titleWords(title)
        if hidden.isEmpty { return sentence }
        let ns = sentence as NSString
        var out = ""
        var at = 0
        for m in word.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            let w = ns.substring(with: m.range)
            out += hidden.contains(stem(fold(w))) ? mask : w
            at = m.range.location + m.range.length
        }
        return out + ns.substring(from: at)
    }

    /// Kotlin `trim()`: Char.isWhitespace at both ends.
    private static func trim(_ s: String) -> String {
        func ws(_ c: Unicode.Scalar) -> Bool {
            switch c.value {
            case 0x09...0x0D, 0x1C...0x1F: return true
            default:
                let g = c.properties.generalCategory
                return g == .spaceSeparator || g == .lineSeparator || g == .paragraphSeparator
            }
        }
        var v = Substring(s).unicodeScalars
        while let f = v.first, ws(f) { v.removeFirst() }
        while let l = v.last, ws(l) { v.removeLast() }
        return String(v)
    }

    /// The article's first sentence, or nil when it's too short to be a clue.
    public static func opening(_ body: String) -> String? {
        let text = replace(spaces, before(trim(body), "\n\n"), " ")
        let ns = text as NSString
        let cut = sentenceEnd.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range.location ?? ns.length
        let first = trim(ns.substring(to: cut))
        let fs = first as NSString
        guard fs.length >= minClue else { return nil }
        if fs.length <= maxClue { return first }
        let head = fs.substring(to: maxClue)
        return reversedSpaceCut(head) + "…"
    }

    /// Kotlin `substringBeforeLast(' ')`: up to the last space, or the whole string when there is none.
    private static func reversedSpaceCut(_ s: String) -> String {
        let r = (s as NSString).range(of: " ", options: [.literal, .backwards])
        return r.location == NSNotFound ? s : (s as NSString).substring(to: r.location)
    }

    /// Today's questions from `articles` (title, body), `count` at most; `epochDay` is the local date's days since
    /// 1970-01-01 (LocalDate.toEpochDay). An article whose opening is too short, or that hides nothing of its title (the
    /// clue would be a guess), is skipped; a small library gives fewer questions.
    public static func daily(_ articles: [(title: String, body: String)], epochDay: Int64, count: Int = 5) -> [Question] {
        var seen = Set<String>()
        let pool = articles.filter { seen.insert(fold($0.title)).inserted }
        if pool.count < 4 { return [] }
        var rnd = KotlinRandom(seed: epochDay)
        let order = rnd.shuffled(pool)
        var out: [Question] = []
        for (title, body) in order {
            if out.count >= count { break }
            guard let opening = opening(body) else { continue }
            let clue = mask(opening, title: title)
            if !clue.contains(mask) { continue }
            let folded = fold(title)
            let others = Array(rnd.shuffled(order.map(\.title).filter { fold($0) != folded }).prefix(3))
            if others.count < 3 { continue }
            let at = rnd.nextInt(4)
            var options = others
            options.insert(title, at: at)
            out.append(Question(clue: clue, options: options, answer: at))
        }
        return out
    }

    /// LocalDate.toEpochDay for `date` in `calendar`'s time zone.
    public static func epochDay(_ date: Date, calendar: Calendar = .current) -> Int64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
        return Int64((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }
}
