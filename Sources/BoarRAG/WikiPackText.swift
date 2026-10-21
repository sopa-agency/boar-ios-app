import Foundation

/// Which source library a format-2 pack article comes from.
public enum PackSource: String, Sendable, CaseIterable, Hashable {
    case enwiki, enwikivoyage, enwikibooks, appropedia, usgov, eips, ethspecs, ethereumorg, bips

    /// The id the TS uses ("enwiki", "enwikivoyage", …).
    public var key: String { rawValue }
}

public struct Stem: Sendable, Equatable {
    public var stem: String
    public var idf: Double
    public init(stem: String, idf: Double) { self.stem = stem; self.idf = idf }
}

/// A ranked BM25 chunk before its text is read.
public struct Candidate: Sendable, Equatable {
    public var chunkId: Int64
    public var articleId: Int64
    public var start: Int
    public var end: Int
    public var score: Double
}

public struct PackArticle: Sendable, Equatable {
    public var id: Int64
    public var title: String
    public var source: PackSource
    public var views: Int64
    public var text: String
    public var url: String?
    public var license: String?
}

public struct PackHit: Sendable, Equatable {
    public var articleId: Int64
    public var chunkId: Int64
    public var title: String
    /// Heading path of the passage ("History > Early years"), "" for the lead.
    public var section: String
    public var text: String
    public var start: Int
    public var end: Int
    public var score: Double
    /// "title": named by the question; "bm25": whole-index keyword hit.
    public var via: String
    public var source: PackSource
    public var views: Int64
    public var lead: Bool
    /// The passage tells what to do (Treatment, First aid, During an earthquake…).
    public var action: Bool
    public var url: String?
    public var license: String?

    public init(
        articleId: Int64, chunkId: Int64, title: String, section: String, text: String, start: Int, end: Int, score: Double, via: String,
        source: PackSource, views: Int64, lead: Bool, action: Bool, url: String? = nil, license: String? = nil
    ) {
        self.articleId = articleId; self.chunkId = chunkId; self.title = title; self.section = section; self.text = text
        self.start = start; self.end = end; self.score = score; self.via = via; self.source = source; self.views = views
        self.lead = lead; self.action = action; self.url = url; self.license = license
    }
}

public struct PackSearchOptions: Sendable {
    public var titles: [String]
    public var k: Int
    public var action: Bool?
    public var explain: Bool?
    public var minHits: Int
    public var queryVec: [Float]?
    public var expand: (@Sendable (String) -> [String])?

    public init(
        titles: [String] = [], k: Int = 6, action: Bool? = nil, explain: Bool? = nil, minHits: Int = 2,
        queryVec: [Float]? = nil, expand: (@Sendable (String) -> [String])? = nil
    ) {
        self.titles = titles; self.k = k; self.action = action; self.explain = explain; self.minHits = minHits
        self.queryVec = queryVec; self.expand = expand
    }
}

public struct PackTuning: Sendable, Equatable {
    /// bm25() column weights: title, section heading, body.
    public var weights: [Double] = [2.0, 1.0, 1.0]
    /// Popularity prior: + prior × log10(1 + monthly views).
    public var prior: Double = 0.5
    public var namedMinShare: Double = WikiPackText.namedMinShare
    public var pool: Int = 80
    public var semanticWeight: Double = 0.0
    public init() {}
}

/// The pure helpers of wikiPack.ts.
public enum WikiPackText {
    public static let namedMinShare = 0.5
    public static let semanticKeep = 0.7
    public static let longTailViews = 5000
    private static let stepsShare = 0.35

    // JavaScript /i also folds non-ASCII letters ("Água"); ICU's (?i) does too. JS $ without /m is end of input: \z.
    private static let b0 = Js.b0
    private static let b1 = Js.b1
    private static let s = Js.ws

    static let actionIntent = Rx(
        "(?i)\(b0)(what (do|should|can|must) (i|we|you) do|what to do|how (do|can|should) (i|we|you) (treat|stop|help|survive|make|purify|disinfect|respond|care)|"
            + "how to (treat|stop|help|survive|make|purify|disinfect)|treat(ing|ment)?|first aid|stop (a|the)?\(s)*[A-Za-z0-9_]*\(s)*(bleed|nosebleed)|"
            + "o que (eu )?(fa[c\u{00E7}]o|fazer|devo fazer)|como (tratar|parar|socorrer|fa[c\u{00E7}]o|agir|purificar|tornar)|primeiros socorros|socorr|"
            + "\(b0)(stop|treat|first aid)\(s)*[?.!]*\\z)"
    )
    static let actionSection = Rx(
        "(?i)\(b0)(treatment|treating|first aid|management|what to do|during|after|immediate|emergency (care|treatment|response)|how to|steps|response|"
            + "survival|purification|disinfection|rescue|resuscitation|tratamento|primeiros socorros|o que fazer)\(b1)"
    )
    static let backgroundSection = Rx(
        "(?i)\(b0)(prevent(ion|ing)?|signs?|symptoms?|epidemiology|history|causes?|pathophysiology|diagnosis|society|culture|research|etymology|statistics|"
            + "by country|quality by|in (fiction|popular culture)|terminology|classification|see also|preparation|preparedness|prepare|before|forecast[A-Za-z0-9_]*|"
            + "predict[A-Za-z0-9_]*|regulation|testing)\(b1)"
    )
    private static let imperative = Rx(
        "(?i)^(?:[\"\u{201C}]?)(do not|don't|never|always|stay|get|keep|move|go|drop|cover|hold|take|call|apply|remove|cool|wash|press|pinch|lean|lie|sit|stand|put|"
            + "place|use|avoid|check|turn|open|close|leave|seek|shelter|protect|stop|drink|boil|rinse|elevate|raise|loosen|wrap|clean|find|look|listen|help|give|"
            + "try|watch|wait|walk|run|crawl|follow|make|bring|carry|tie|immobili[sz]e|monitor|reassure|if [^,]{1,60}, (?:do not|don't|stay|get|keep|move|go|drop|"
            + "cover|hold|take|call|leave|use|stop))\(b1)"
    )
    private static let sentenceSplit = Rx("(?<=[.!?])\(s)+|\\n+")
    private static let bullet = Rx("^[-*\u{2022}\\d.)\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+")

    public static func hasActionIntent(_ query: String) -> Bool { actionIntent.contains(query) }

    public static func instructionShare(_ text: String) -> Double {
        let sentences = sentenceSplit.split(text).map { Js.trim(bullet.replace($0, with: "")) }.filter { $0.u16Count > 3 }
        return sentences.isEmpty ? 0.0 : Double(sentences.filter { imperative.contains($0) }.count) / Double(sentences.count)
    }

    /// Sections grouped by top heading, groups by best score; a section before its own subsections.
    static func stepsFirst<T: Equatable>(_ items: [T], score: (T) -> Double, sectionOf: (T) -> String) -> [T] {
        func top(_ x: T) -> String { sectionOf(x).components(separatedBy: " > ")[0] }
        var best: [String: Double] = [:]
        for x in items { best[top(x)] = max(best[top(x)] ?? -Double.infinity, score(x)) }
        let byScore = items.stableSorted { a, b in
            let ba = best[top(a)]!, bb = best[top(b)]!
            return ba != bb ? ba > bb : score(a) > score(b)
        }
        var out: [T] = []
        for x in byScore {
            let path = sectionOf(x).components(separatedBy: " > ")
            if path.count > 1 {
                for d in 1..<path.count {
                    let want = path[0..<d].joined(separator: " > ")
                    if let anc = byScore.first(where: { sectionOf($0) == want }), !out.contains(anc) { out.append(anc) }
                }
            }
            if !out.contains(x) { out.append(x) }
        }
        return out
    }

    public static let laySources: Set<PackSource> = [.enwikibooks, .usgov, .enwikivoyage]

    public static func isActionPassage(_ section: String, _ text: String) -> Bool {
        let kind = sectionKind(section)
        return kind.hasPrefix("action") || (kind == "other" && instructionShare(text) >= stepsShare)
    }

    public static func sectionKind(_ section: String) -> String {
        let path = section.components(separatedBy: " > ")
        let leaf = path.last!
        if backgroundSection.contains(leaf) { return "background" }
        if actionSection.contains(leaf) { return "action" }
        let parents = path.dropLast().joined(separator: " > ")
        if actionSection.contains(parents) { return "action-sub" }
        return backgroundSection.contains(parents) ? "background" : "other"
    }

    static let travelIntent = Rx(
        "(?i)\(b0)(visit|visiting|things to (see|do)|what (can|should) (i|we) (see|do)|see and do|travel|trip|get (to|there|around)|getting (to|around)|stay|hotel|"
            + "hostel|eat|restaurants?|sights?|tourists?|itinerary|by (train|bus|car|ferry)|airport)\(b1)"
    )
    private static let travelPractical = Rx(
        "(?i)\(b0)(plugs?|plug types?|voltage|what currency|currency (is )?used|atms?|pay (by|with) (a )?card|tipping|tap water|drinking water|emergency numbers?|"
            + "visas?|driving licen[cs]e|drive on the (left|right)|ride-?hailing|say .+ in|phrasebook|best time to (visit|go|travel)|tomadas?|voltagem|moeda|"
            + "pagar com cart[a\u{00E3}]o|gorjetas?|[a\u{00E1}]gua da torneira|preciso de visto|visto de turista|como (se )?diz|melhor [e\u{00E9}]poca para)\(b1)"
    )
    private static let tripIntent = Rx(
        "(?i)\(b0)(visit|visiting|things to (see|do)|see and do|get (to|there|around)|getting (to|around)|hotels?|hostels?|airports?|tourists?|itinerary|sightseeing)\(b1)"
    )

    public static func isTravelQuestion(_ query: String) -> Bool { tripIntent.contains(query) || travelPractical.contains(query) }

    static let originCue = Rx(
        "(?i)\(b0)(from|live in|living in|lives in|resident of|citizens? of|passport holders? of|compared (to|with)|saindo de|vindo de|partindo de|morando em|"
            + "moro em|cidad[\u{00E3}a]os? d[aeo]s?|comparad[oa] (a|com))\(s)+(the\(s)+|a\(s)+|an\(s)+|o\(s)+|os\(s)+|as\(s)+)?\\z"
    )
    static let placeCue = Rx(
        "(?i)\(b0)(in|to|for|at|around|near|into|across|visit|visiting|does|do|is|are|em|para|pra|no|na|nos|nas|[\u{00E0}a]|ao|aos|[\u{00E0}a]s|visitar|conhecer)\(s)+"
            + "(the\(s)+|a\(s)+|an\(s)+|o\(s)+|os\(s)+|as\(s)+)?\\z"
    )
    static let questionWords: Set<String> = [
        "what", "when", "where", "why", "how", "who", "which", "whose", "is", "are", "can", "do", "does", "did", "should", "tell",
        "como", "quando", "onde", "porque", "por", "qual", "quais", "quem", "quanto", "quantos", "o", "a", "os", "as", "\u{00E9}", "existe",
    ]
    static let foreignFunctionWords: Set<String> = Set((
        "o os a as um uma uns umas de do da dos das em no na nos nas num numa por para com sem que como qual quais quando onde "
            + "porque se ao aos el la los las un una del al en con por para que como cual cuando donde es son y e ou"
    ).components(separatedBy: " "))
    static let actionWords: Set<String> = ["stop", "treat", "help", "first", "aid", "handl", "respond", "surviv"]
    static let stopwords: Set<String> = Set((
        "a about above after again against all also am an and any are as at be because been before being below "
            + "between both but by can could compare comparison describe did difference differences do does doing down "
            + "during each explain few for from further give had has have having he her here hers him his how i if in "
            + "into is it its itself just know like me mean means more most much my no nor not now of off on once only "
            + "or other our out over own please same she should show so some such summarize tell than that the their "
            + "them then there these they this those through to too under until up us very versus vs was we were what "
            + "when where which while who whom whose why will with would you your"
    ).components(separatedBy: " "))

    private static let headingRx = Rx("(?m)^(#{1,6})\(s)+([^\\n\\r\\u0085\\u2028\\u2029]*)$")

    private struct Heading { var at: Int; var level: Int; var titleAt: Int; var lineEnd: Int; var title: String }

    private final class HeadingCache: @unchecked Sendable {
        private let lock = NSLock()
        private var text: String?
        private var headings: [Heading] = []
        func get(_ t: String) -> [Heading] {
            lock.lock(); defer { lock.unlock() }
            if let text, text == t { return headings }
            let out = WikiPackText.headingRx.all(t).map { m -> Heading in
                let title = m.group(2) ?? ""
                let lineEnd = m.start + m.value.u16Count
                return Heading(at: m.start, level: (m.group(1) ?? "").u16Count, titleAt: lineEnd - title.u16Count, lineEnd: lineEnd, title: title)
            }
            text = t
            headings = out
            return out
        }
    }
    private static let headingCache = HeadingCache()

    /// Heading path in force at offset `start` (chunks store offsets only).
    public static func sectionAt(_ text: String, _ start: Int) -> String {
        var path: [String] = []
        for h in headingCache.get(text) {
            if h.at >= start { break }
            while path.count > h.level - 1 { path.removeLast() }
            while path.count < h.level - 1 { path.append("") }
            path.append(Js.trim(h.lineEnd > start ? text.u16Sub(h.titleAt, start) : h.title))
        }
        return path.dropFirst().filter { !$0.isEmpty }.joined(separator: " > ")
    }

    /// FTS5 term for a stem; a stem ending in "i" (porter's y) matches as a prefix of the stem without it.
    public static func matchTerm(_ stem: String) -> String {
        func q(_ t: String) -> String { "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return stem.u16EndsWith("i") && stem.u16Count > 4 ? q(stem.u16DropLast(1)) + "*" : q(stem)
    }

    static func prefixOf(_ stem: String) -> String { stem.u16EndsWith("i") && stem.u16Count > 3 ? stem.u16DropLast(1) : stem }

    /// JavaScript /[\p{L}\p{N}]/u on one UTF-16 unit (a lone surrogate never matches).
    static func isWordChar(_ c: UInt16) -> Bool {
        if (0xD800...0xDFFF).contains(c) { return false }
        guard let u = Unicode.Scalar(c) else { return false }
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// Occurrences of `prefix` in `text` that don't follow a letter or digit (a word-start match).
    static func countAtBoundary(_ prefix: String, _ text: String, firstOnly: Bool = false) -> Int {
        let p = Array(prefix.utf16), t = Array(text.utf16)
        if p.isEmpty { return firstOnly ? 1 : t.count + 1 }
        var n = 0
        if t.count < p.count { return 0 }
        var i = 0
        while i <= t.count - p.count {
            var match = true
            var k = 0
            while k < p.count { if t[i + k] != p[k] { match = false; break }; k += 1 }
            if match {
                if !(i > 0 && isWordChar(t[i - 1])) {
                    n += 1
                    if firstOnly { break }
                }
            }
            i += 1
        }
        return n
    }

    private static let words = Rx("[\\p{L}\\p{N}]+")

    public static func nearDuplicate(_ a: String, _ b: String, threshold: Double = 0.5) -> Bool {
        func grams(_ t: String) -> Set<String> {
            let w = words.all(t.lowercased()).map(\.value)
            if w.count < 5 { return [] }
            return Set((0...(w.count - 5)).map { w[$0..<($0 + 5)].joined(separator: " ") })
        }
        let ga = grams(a), gb = grams(b)
        if ga.isEmpty || gb.isEmpty { return false }
        let both = ga.filter { gb.contains($0) }.count
        return Double(both) / Double(ga.count + gb.count - both) >= threshold
    }

    static func coverage(_ text: String, _ stems: [Stem]) -> Double {
        let low = text.lowercased()
        var total = stems.reduce(0.0) { $0 + $1.idf }
        if total == 0.0 { total = 1.0 }
        let hit = stems.filter { countAtBoundary(prefixOf($0.stem), low, firstOnly: true) > 0 }.reduce(0.0) { $0 + $1.idf }
        return hit / total
    }

    private static let candWord = Rx("[\\p{L}\\p{N}][\\p{L}\\p{N}'\u{2019}.-]*")
    private static let trail = Rx("[.'\u{2019}-]+$")

    /// Word n-grams of the question that could be article titles, longest first.
    public static func titleCandidates(_ query: String, maxLen: Int = 5) -> [String] {
        let clean = candWord.all(query).map { trail.replace($0.value, with: "") }
        var out: [String] = []
        var seen = Set<String>()
        for len in stride(from: min(maxLen, clean.count), through: 1, by: -1) {
            for i in 0...(clean.count - len) {
                let gram = Array(clean[i..<(i + len)])
                if stopwords.contains(gram[0].lowercased()) || stopwords.contains(gram[len - 1].lowercased()) { continue }
                if gram.allSatisfy({ stopwords.contains($0.lowercased()) }) { continue }
                let title = gram.joined(separator: " ")
                if seen.insert(title.lowercased()).inserted { out.append(title) }
            }
        }
        return out
    }

    private static let ies = Rx("(?i)ies$")
    private static let plural = Rx("(?i)[^s]s$")

    static func singularTitle(_ title: String) -> String? {
        if ies.contains(title) { return ies.replace(title, with: "y") }
        if plural.contains(title) && title.u16Count > 4 { return title.u16DropLast(1) }
        return nil
    }

    /// JavaScript Math.round.
    static func jsRound2(_ x: Double) -> Double { ((x * 100 + 0.5).rounded(.down)) / 100 }
}
