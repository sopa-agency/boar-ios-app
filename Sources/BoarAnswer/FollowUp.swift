import BoarRAG
import BoarRouting
import Foundation

/// What to search the library for when the question is a follow-up (port of src/routing/followUp.ts).
///
/// Retrieval saw only the question's own words, so a follow-up found nothing: "What did he publish?" after a Darwin
/// answer. From the conversation's previous question:
/// - a question that points back ("he", "it", "isso"…) is searched together with the previous question, and with the
///   previous question alone when that finds nothing;
/// - a short question with no name of its own is searched as written first, and with the previous question only when
///   that finds nothing. A question that finds sources keeps them, and one with a name never borrows another topic.
public enum FollowUp {
    /// Words that only make sense with an earlier subject (English and Portuguese); "there" is checked apart (`thereAsPlace`).
    private static let pointsBack = Rx(
        "(?:^|[^\\p{L}])(he|she|it|its|they|them|their|theirs|him|his|her|hers|this|that|these|those|ele|ela|eles|elas|dele|dela|deles|delas|isso|isto|aquilo|nele|nela|esse|essa|esses|essas)(?![\\p{L}])",
        ignoreCase: true
    )

    /// Words around an existential "there" ("Is there a cure?", "There are two kinds"), which points at nothing earlier.
    private static let existentialBefore: Set<String> = ["is", "are", "was", "were", "be", "been", "isn't", "aren't", "wasn't", "weren't"]
    private static let existentialAfter: Set<String> = [
        "is", "are", "was", "were", "be", "been", "isn't", "aren't", "wasn't", "weren't", "will", "would", "could", "might",
        "may", "must", "seem", "seems", "appear", "appears", "exist", "exists", "remain", "remains", "used",
    ]
    private static let notWord = Rx("[^\\p{L}']+")

    /// "there" as a place ("What happened there?"), not the existential "is there" of a question that brings its own subject.
    private static func thereAsPlace(_ query: String) -> Bool {
        let words = notWord.split(query.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")).filter { !$0.isEmpty }
        for (i, w) in words.enumerated() where w == "there" {
            let before = i > 0 ? words[i - 1] : nil
            let after = i + 1 < words.count ? words[i + 1] : nil
            if !(before.map(existentialBefore.contains) ?? false) && !(after.map(existentialAfter.contains) ?? false) { return true }
        }
        return false
    }

    /// Words a question or request starts with, capitalized only because they open it (English and Portuguese).
    private static let openers: Set<String> = [
        "what", "whats", "who", "whos", "whom", "whose", "which", "when", "whens", "where", "wheres", "why",
        "whys", "how", "hows", "is", "are", "was", "were", "am", "be", "do", "does", "did",
        "can", "could", "should", "would", "will", "shall", "may", "might", "must", "have", "has", "had",
        "tell", "explain", "describe", "compare", "list", "give", "show", "define", "summarize", "summarise", "name", "find",
        "write", "help", "please", "and", "but", "or", "so", "then", "also", "now", "ok", "okay",
        "i", "you", "we", "they", "he", "she", "it", "there", "theres", "here", "heres", "a",
        "an", "the", "any", "some", "my", "your", "in", "on", "at", "for", "of", "to",
        "from", "with", "about", "between", "after", "before", "during", "if", "o", "os", "as", "um",
        "uma", "uns", "umas", "qual", "quais", "quem", "como", "quando", "onde", "por", "porque", "porquê",
        "que", "quê", "e", "mas", "ou", "então", "também", "agora", "me", "fale", "explique", "descreva",
        "compare", "liste", "diga", "mostre", "defina", "resuma", "é", "são", "foi", "foram", "era", "há",
        "tem", "têm", "existe", "existem", "eu", "você", "voce", "nós", "ele", "ela", "isso", "isto",
        "no", "na", "nos", "nas", "do", "da", "dos", "das", "de", "em", "para", "com",
        "sobre", "entre", "depois", "antes", "durante", "se",
    ]
    private static let afterWord = Rx("[^\\p{L}0-9]+.*$")

    /// At most this many content words for a question to borrow the previous one's topic when it finds nothing.
    public static let shortFollowUpTerms = 3

    /// `direct`: search this instead of the question (it points back); `previous`: with `direct`, the previous question
    /// alone when the combined text finds nothing; `fallback`: search this only if the question alone found nothing.
    public struct Plan: Sendable, Equatable {
        public var direct: String?
        public var previous: String?
        public var fallback: String?
        public init(direct: String? = nil, previous: String? = nil, fallback: String? = nil) {
            self.direct = direct; self.previous = previous; self.fallback = fallback
        }
    }

    /// The chunks found, and the text that found them (the caller compresses against the same words).
    public struct Found<T: Sendable>: Sendable {
        public var chunks: [T]
        public var searchedFor: String
        public init(chunks: [T], searchedFor: String) { self.chunks = chunks; self.searchedFor = searchedFor }
    }

    private static let spaces = Rx("\(JsString.ws)+")
    private static let openingMark = Rx("^[\"'(«“]")
    private static let capitalOrDigit = Rx("^[\\p{Lu}0-9]")

    /// The latest earlier question, never the current one (a history that already holds it would make it its own subject).
    private static func previousQuestion(_ query: String, _ history: ConversationHistory?) -> String? {
        let turns = history?.turns ?? []
        let current = JsString.trim(query)
        for t in turns.reversed() {
            let text = JsString.trim(t.text)
            if t.role == "user" && !text.isEmpty && text != current { return text }
        }
        return nil
    }

    /// A name the question brings itself ("Australia", "EIP-1559"): a capitalized word or one starting with a digit. The first
    /// word counts too ("Australia capital?"), unless it is one a question usually opens with.
    private static func namesItsOwnSubject(_ query: String) -> Bool {
        for (i, w) in spaces.split(JsString.trim(query)).enumerated() {
            let bare = openingMark.replaceFirst(w, with: "")
            guard capitalOrDigit.containsMatch(in: bare) else { continue }
            if i > 0 { return true }
            let word = afterWord.replaceFirst(bare.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "'", with: ""), with: "")
            if !openers.contains(word) { return true }
        }
        return false
    }

    public static func plan(_ query: String, _ history: ConversationHistory?) -> Plan {
        guard let previous = previousQuestion(query, history) else { return Plan() }
        let combined = "\(previous) \(JsString.trim(query))"
        if pointsBack.containsMatch(in: query) || thereAsPlace(query) { return Plan(direct: combined, previous: previous) }
        if Compress.tokenizeTerms(query).count <= shortFollowUpTerms && !namesItsOwnSubject(query) { return Plan(fallback: combined) }
        return Plan()
    }

    /// The passages the fallback found that share at least one of the question's own content words (stemmed, as retrieval
    /// does): a question that found nothing because of a typo ("what is a moonsoon", after a greenhouse-effect question) got
    /// the earlier topic's passages as its sources. No content words of its own: all kept.
    public static func aboutTheQuestion<T>(_ query: String, _ chunks: [T], textOf: (T) -> String) -> [T] {
        let own = Set(Compress.tokenizeTerms(query))
        if own.isEmpty { return chunks }
        return chunks.filter { c in Compress.tokenizeTerms(textOf(c)).contains(where: own.contains) }
    }

    /// Runs `find` (the text to search → its chunks) with the follow-up rule. With `textOf`, the fallback keeps only the
    /// passages about the question (`aboutTheQuestion`).
    public static func search<T: Sendable>(
        _ query: String, history: ConversationHistory?, textOf: ((T) -> String)? = nil, find: (String) async throws -> [T]
    ) async throws -> Found<T> {
        let p = plan(query, history)
        if let direct = p.direct {
            let chunks = try await find(direct)
            guard chunks.isEmpty, let previous = p.previous else { return Found(chunks: chunks, searchedFor: direct) }
            // Found by the earlier subject; compressed against the combined words, so the sentences closest to the
            // follow-up ("publish") are the ones kept.
            return Found(chunks: try await find(previous), searchedFor: direct)
        }
        let chunks = try await find(query)
        guard chunks.isEmpty, let fallback = p.fallback else { return Found(chunks: chunks, searchedFor: query) }
        let found = try await find(fallback)
        let kept = textOf.map { aboutTheQuestion(query, found, textOf: $0) } ?? found
        return Found(chunks: kept, searchedFor: kept.isEmpty ? query : fallback)
    }
}
