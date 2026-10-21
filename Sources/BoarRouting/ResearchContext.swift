import Foundation

/// The text helpers of the retrieval layer (Kotlin `rag.Compress.tokenizeTerms` / `splitSentences`) that the on-topic
/// test needs. The routing target does not depend on BoarRAG, so the caller (BoarAnswer) supplies them.
public protocol ResearchTextTools: Sendable {
    /// Lower-cased, accent-stripped, stop-word-free, stemmed terms of a text.
    func tokenizeTerms(_ text: String) -> [String]
    /// Sentences of a text (abbreviations and decimals kept intact).
    func splitSentences(_ text: String) -> [String]
}

/// What the on-topic test reads of a retrieved passage (Kotlin `rag.Chunk`).
public protocol ResearchPassage: Sendable {
    var chunkId: String { get }
    var title: String { get }
    var body: String { get }
}

/// What Deep Research needs from src/routing/context.ts: the on-topic test for a source (onTopic and its helpers) and
/// mergeSources. `compressContext` is `Compress.compress(query, chunks, tokenBudget: 1200, maxSentencesPerChunk: 4,
/// pinned: [], openingMustFitWithMatch: false, withRelevance: true)` and lives with Compress in BoarRAG. Regex sources
/// are the TypeScript's, translated by `JsRegex`.
public struct ResearchContext: Sendable {
    /// Below this, a source counts as weak (MIN_TERM_COVERAGE).
    public static let minTermCoverage = 0.75
    private static let titleMinCoverage = 0.5
    public static let minTermsForCoverage = 3

    private let tools: any ResearchTextTools

    public init(tools: any ResearchTextTools) {
        self.tools = tools
    }

    private func terms(_ text: String) -> [String] { tools.tokenizeTerms(text) }

    /// termCoverage: share of the question's distinct content words found in [text].
    public func termCoverage(query: String, text: String) -> Double {
        let q = Self.distinct(terms(query))
        if q.isEmpty { return 1.0 }
        let t = Set(terms(text))
        return Double(q.filter { t.contains($0) }.count) / Double(q.count)
    }

    private static func distinct(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.filter { seen.insert($0).inserted }
    }

    /// Same word despite the tiny stemmer ("earthquak"/"earthquake"); a longer suffix is another word.
    private static func sameTerm(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.utf16.count <= b.utf16.count ? (a, b) : (b, a)
        return short.utf16.count >= 5 && long.hasPrefix(short) && long.utf16.count - short.utf16.count <= 3
    }

    private static let compounds: [String: [String]] = [
        "snakebite": ["snake", "bite"],
        "nosebleed": ["nose", "bleed"],
        "heatstroke": ["heat", "stroke"],
        "frostbite": ["frost", "bite"],
    ]
    private static let compoundPart: [String: JsRegex] = {
        var m: [String: JsRegex] = [:]
        for p in compounds.values.joined() where m[p] == nil { m[p] = JsRegex("\\b\(p)(s|es)?\\b", flags: "i") }
        return m
    }()

    private func titleNames(_ title: String, _ ts: Set<String>) -> Bool {
        let t = terms(title)
        for q in ts {
            if t.contains(where: { Self.sameTerm($0, q) }) { return true }
            // Parts on the raw words: the tiny stemmer turns "bites" into "bit".
            if let parts = Self.compounds[q], parts.allSatisfy({ Self.compoundPart[$0]!.containsMatch(in: title) }) { return true }
        }
        return false
    }

    /// UTF-16 offset of the first ':' in [s].
    private static func colonOffset(_ s: String) -> Int? {
        s.utf16.firstIndex(of: 58).map { s.utf16.distance(from: s.utf16.startIndex, to: $0) }
    }

    /// A pack chunk's section path ("During your trip > … > Water contamination"), or "".
    private static func sectionHeading(_ body: String) -> String {
        if let colon = colonOffset(body), colon >= 1, colon <= 120 { return (body as NSString).substring(to: colon) }
        return ""
    }

    private static let year = JsRegex(#"(?<![\d.,])(1[0-9]{3}|20[0-9]{2})(?![\d.,]?\d)"#, flags: "g")
    private static func yearsIn(_ text: String) -> [String] { year.findAll(in: text).map(\.value) }

    private static let word = JsRegex(#"[\p{L}][\p{L}\p{N}'’-]*"#, flags: "gu")
    private static let upper = JsRegex(#"^\p{Lu}"#, flags: "u")
    private func properNounTerms(_ query: String) -> [String] {
        Self.word.findAll(in: query).map(\.value).dropFirst().filter { Self.upper.containsMatch(in: $0) && $0 != "I" }.flatMap { terms($0) }
    }

    private static let combining = JsRegex(#"[\u0300-\u036f]"#)
    private static let az09 = JsRegex("[a-z0-9]+")
    private static let place: Set<String> = ["in", "at", "near", "to", "into", "from", "em", "no", "na", "perto"]
    private static let commaSplit = JsRegex(#",\s+"#)

    /// Lead text of a passage past its "Section:" heading (cut at [limit] characters, as onTopic does).
    private static func pastHeading(_ body: String, _ limit: Int) -> String {
        if let colon = colonOffset(body), colon >= 1, colon <= limit { return (body as NSString).substring(from: colon + 1) }
        return body
    }

    private func firstSentence(_ text: String) -> String { tools.splitSentences(JsString.trim(text)).first ?? "" }

    /// Two consecutive question terms appear, consecutive, in the title or the first sentence, not as a place.
    private func sharesQuestionPair(_ query: String, title: String, body: String) -> Bool {
        let qt = terms(query)
        let pairs = qt.indices.dropFirst().map { (qt[$0 - 1], qt[$0]) }.filter { $0.0 != $0.1 }
        if pairs.isEmpty { return false }
        func has(_ raw: String) -> Bool {
            let nfkd = Self.combining.replace(in: raw.lowercased().decomposedStringWithCompatibilityMapping, with: "")
            let words: [(String, String?)] = Self.az09.findAll(in: nfkd).map(\.value).map { ($0, terms($0).first) }
            return pairs.contains { a, b in
                words.indices.contains { i in
                    i + 1 < words.count && words[i].1 != nil && words[i + 1].1 != nil
                        && Self.sameTerm(words[i].1!, a) && Self.sameTerm(words[i + 1].1!, b)
                        && !(i > 0 && Self.place.contains(words[i - 1].0))
                }
            }
        }
        return has(Self.commaSplit.split(title)[0]) || has(firstSentence(Self.pastHeading(body, 120)))
    }

    private func leadsTitle(_ title: String, _ q: Set<String>) -> Bool {
        guard let first = terms(title).first else { return false }
        return q.contains { Self.sameTerm(first, $0) }
    }

    private static let sourceLabel = JsRegex(#"^(Wikipedia|Wikibooks|Wikivoyage|US government|Appropedia|ethereum\.org|Ethereum EIPs\/ERCs|Ethereum specs|Bitcoin BIPs):\s*"#)
    private static let titleSep = JsRegex(#":\s+"#)
    private static let trailingParen = JsRegex(#"\s*\([^)]*\)\s*$"#)
    private static func mainTitle(_ title: String) -> String { titleSep.split(sourceLabel.replaceFirst(in: title, with: ""))[0] }

    private func titleSegmentNamed(_ title: String, _ q: Set<String>) -> Bool {
        Self.titleSep.split(title).contains { seg in
            let st = terms(Self.trailingParen.replaceFirst(in: seg, with: ""))
            return !st.isEmpty && st.allSatisfy { q.contains($0) }
        }
    }

    private static let acronym = JsRegex(#"\(([A-Z][A-Z0-9-]{1,9})\)\s*$"#)

    /// onTopic: whether a source is about the question (see context.ts for the cases each rule comes from).
    public func onTopic(query: String, title: String, body: String) -> Bool {
        let q = Set(terms(query))
        let text = "\(title) \(body)"
        // A year or a proper noun in the question must be in the source.
        let years = Self.yearsIn(text)
        if !Self.yearsIn(query).allSatisfy({ years.contains($0) }) { return false }
        let proper = properNounTerms(query)
        if !proper.isEmpty {
            let words = Set(terms(text))
            if !proper.contains(where: { words.contains($0) }) { return false }
        }
        if titleSegmentNamed(title, q) { return true }
        if sharesQuestionPair(query, title: title, body: body) { return true }
        if let ac = Self.acronym.find(in: title)?.group(1), q.contains(terms(ac).first ?? "") { return true }
        if leadsTitle(Self.mainTitle(title), q) { return true }
        if titleNames(title, q) || titleNames(Self.sectionHeading(body), q) {
            return termCoverage(query: query, text: text) >= (q.count < Self.minTermsForCoverage ? 1.0 : Self.titleMinCoverage)
        }
        // One or two content words: the passage must open with them.
        if q.count < Self.minTermsForCoverage {
            let first = Set(terms(firstSentence(Self.pastHeading(body, 80))))
            return !q.isEmpty && q.allSatisfy { first.contains($0) }
        }
        return termCoverage(query: query, text: text) >= Self.minTermCoverage
    }

    public func onTopic(query: String, _ passage: some ResearchPassage) -> Bool {
        onTopic(query: query, title: passage.title, body: passage.body)
    }

    public struct Merged<P: ResearchPassage>: Sendable {
        public var sources: [P]
        public var indexMaps: [[Int]]
    }

    /// mergeSources: one global numbered list; the same chunk from two lists gets one number.
    public static func mergeSources<P: ResearchPassage>(_ lists: [[P]]) -> Merged<P> {
        var sources: [P] = []
        var byId: [String: Int] = [:]
        let maps = lists.map { list in
            list.map { c -> Int in
                if let i = byId[c.chunkId] { return i }
                sources.append(c)
                byId[c.chunkId] = sources.count - 1
                return sources.count - 1
            }
        }
        return Merged(sources: sources, indexMaps: maps)
    }
}
