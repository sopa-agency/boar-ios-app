import Foundation

/// Sends the model only the sentences that answer the question (port of src/rag/compress.ts): every sentence of
/// the retrieved passages is scored against the question (IDF-weighted term coverage), the best are kept up to a
/// token budget, each kept passage opens with its first sentence, and passages far less relevant than the best
/// are dropped. Regexes spell out JavaScript's semantics (Unicode \s, ASCII \b) so the output matches the TS.
public enum Compress {
    public struct ScoredSentence: Sendable, Equatable {
        public var chunkIndex: Int
        public var position: Int
        public var text: String
        public var score: Double
    }

    public struct Result: Sendable, Equatable {
        public var chunks: [Chunk]
        public var keptIndices: [Int]
        public var tokensBefore: Int
        public var tokensAfter: Int
    }

    public static let relativeRelevanceFloor = 0.5
    private static let fillMaxTokens = 60
    public static let fastLookupTokens = 450
    public static let fastOtherTokens = 700

    private static let stopwords: Set<String> = Set((
        "a an the and or but if then else of to in on at by for with from as is are was were be been being "
            + "do does did doing have has had having it its this that these those there here what which who whom whose "
            + "when where why how can could should would will shall may might must i you he she we they me him her us them "
            + "my your his our their not no yes so than too very just about into over under between vs versus also "
            + "tell explain describe give me please much many more most some any all each other such only own same "
            + "o a os as um uma de do da dos das em no na nos nas por para com que qual quais quem como quando onde porque \u{00E9}"
    ).split(whereSeparator: { $0 == " " }).map(String.init))

    private static let term = Rx("[a-z0-9]+")

    public static func tokenizeTerms(_ text: String) -> [String] {
        let folded = Js.combining.replace(Js.nfkd(text.lowercased()), with: "")
        return term.all(folded).map(\.value).filter { $0.count > 1 && !stopwords.contains($0) }.map(stem)
    }

    /// Terms are ASCII (`[a-z0-9]+`), so Swift and UTF-16 lengths agree.
    private static func stem(_ t: String) -> String {
        if t.count > 5 && t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.count > 4 && (t.hasSuffix("es") || t.hasSuffix("ed")) { return String(t.dropLast(2)) }
        if t.count > 3 && t.hasSuffix("s") && !t.hasSuffix("ss") { return String(t.dropLast(1)) }
        if t.count > 5 && t.hasSuffix("ing") { return String(t.dropLast(3)) }
        return t
    }

    private static let heading = Rx("(?m)^#{1,6}\(Js.ws)+")
    private static let wrap = Rx("([^\\n])\\n(?!\\n)(?=[a-z(])|([ ,(\\-\u{2013}])\\n(?!\\n)")
    private static let spaces = Rx(" {2,}")

    private static func unwrapLines(_ text: String) -> String {
        let a = heading.replace(text, with: "")
        let b = wrap.replace(a) { m in
            if let g1 = m.group(1) { return g1 + " " }
            return m.group(2) ?? ""
        }
        return spaces.replace(b, with: " ")
    }

    private static let boundary = Rx("[.!?]+[\"')\\]]*\(Js.ws)+(?=[\"'(\\[]?[A-Z0-9])|\\n+")
    private static let nb = Js.b0
    private static let abbrev = Rx("(?:\(nb)[A-Z]|\(nb)(?:e\\.g|i\\.e|etc|vs|Mr|Mrs|Dr|St|No|approx|c|ca))\\.$")

    /// Sentence split that keeps abbreviations and decimals ("U.S.", "3.5", "e.g.") intact; newlines split too.
    public static func splitSentences(_ input: String) -> [String] {
        let text = unwrapLines(input) as NSString
        let whole = text as String
        var out: [String] = []
        var start = 0
        for m in boundary.all(whole) {
            let value = m.value
            let end = m.start + Js.trimEnd(value).u16Count
            let candidate = text.substring(with: NSRange(location: start, length: max(0, end - start)))
            if value.utf16.first == 0x2E && abbrev.contains(Js.trimEnd(candidate)) { continue }
            let t = Js.trim(candidate)
            if !t.isEmpty { out.append(t) }
            start = m.end
        }
        let rest = text.substring(from: min(start, text.length))
        let r = Js.trim(rest)
        if !r.isEmpty { out.append(r) }
        return out
    }

    public static func scoreSentences(_ query: String, _ chunks: [Chunk]) -> [ScoredSentence] {
        var qTerms: [String] = []
        var qSeen = Set<String>()
        for t in tokenizeTerms(query) where qSeen.insert(t).inserted { qTerms.append(t) }
        struct S { var chunkIndex: Int; var position: Int; var text: String; var terms: Set<String> }
        var all: [S] = []
        for (ci, c) in chunks.enumerated() {
            for (p, t) in splitSentences(c.body).enumerated() { all.append(S(chunkIndex: ci, position: p, text: t, terms: Set(tokenizeTerms(t)))) }
        }
        if qTerms.isEmpty { return all.map { ScoredSentence(chunkIndex: $0.chunkIndex, position: $0.position, text: $0.text, score: 0.0) } }
        let n = all.count
        var idf: [String: Double] = [:]
        for t in qTerms {
            let df = all.reduce(0) { $0 + ($1.terms.contains(t) ? 1 : 0) }
            idf[t] = log(1 + Double(n + 1) / (Double(df) + 0.5))
        }
        let total = qTerms.reduce(0.0) { $0 + idf[$1]! }
        let qSet = Set(qTerms)
        let sep = Rx(":\(Js.ws)+")
        let named: [Set<String>] = chunks.map { c in
            var terms = Set<String>()
            for seg in sep.split(c.title) {
                let st = tokenizeTerms(seg)
                if !st.isEmpty && st.allSatisfy({ qSet.contains($0) }) { terms.formUnion(st) }
            }
            return terms
        }
        let titleHits: [Bool] = chunks.map { c in tokenizeTerms(c.title).contains(where: { qSet.contains($0) }) }
        return all.map { s in
            var covered = 0.0
            for t in qTerms where s.terms.contains(t) || named[s.chunkIndex].contains(t) { covered += idf[t]! }
            let titleHit = titleHits[s.chunkIndex] ? 0.1 : 0.0
            return ScoredSentence(chunkIndex: s.chunkIndex, position: s.position, text: s.text, score: min(1.0, covered / total + (covered > 0 ? titleHit : 0.0)))
        }
    }

    private static let namedArticleRelevance = 0.75
    private static let titleSep = Rx(":\(Js.ws)+")
    private static let trailingParen = Rx("\(Js.ws)*\\([^)]*\\)\(Js.ws)*\\z")

    /// ~4 characters per token (UTF-16 length, as in JS).
    public static func approxTokens(_ s: String) -> Int { Int((Double(s.u16Count) / 4.0).rounded(.up)) }

    /// - openingMustFitWithMatch: a new passage is opened only when its first sentence fits together with the one that
    ///   matched (src/rag/compress.ts); false keeps src/routing/context.ts's older check (title and match only).
    /// - withRelevance: set `Chunk.relevance` as context.ts's compressContext does.
    public static func compress(
        _ query: String, _ chunks: [Chunk], tokenBudget: Int = 1200, maxSentencesPerChunk: Int = 4, pinned: Set<String> = [],
        count: (String) -> Int = approxTokens, openingMustFitWithMatch: Bool = true, withRelevance: Bool = false
    ) -> Result {
        let tokensBefore = chunks.reduce(0) { $0 + count("\($1.title)\n\($1.body)") }
        let scored = scoreSentences(query, chunks)
        let anyMatch = scored.contains { $0.score > 0 }
        let chunkBest: [Double] = chunks.indices.map { ci in
            max(0.0, scored.filter { $0.chunkIndex == ci }.map(\.score).max() ?? 0.0)
        }
        let topBest = max(0.0, chunkBest.max() ?? 0.0)
        let pinnedIdx = Set(chunks.indices.filter { pinned.contains(chunks[$0].chunkId) })
        func relevant(_ ci: Int) -> Bool { pinnedIdx.contains(ci) || !anyMatch || chunkBest[ci] >= relativeRelevanceFloor * topBest }
        func byRank(_ a: ScoredSentence, _ b: ScoredSentence) -> Bool {
            if a.score != b.score { return a.score > b.score }
            if a.chunkIndex != b.chunkIndex { return a.chunkIndex < b.chunkIndex }
            return a.position < b.position
        }
        var ranked = (anyMatch ? scored.filter { $0.score > 0 && relevant($0.chunkIndex) } : scored.filter { $0.position == 0 }).stableSorted(by: byRank)
        if !pinnedIdx.isEmpty {
            let opening = scored.filter { pinnedIdx.contains($0.chunkIndex) && $0.position == 0 }
            ranked = opening + ranked.filter { pinnedIdx.contains($0.chunkIndex) && $0.position != 0 } + ranked.filter { !pinnedIdx.contains($0.chunkIndex) }
        }

        var picked: [Int: Set<Int>] = [:]
        var used = 0
        func cost(_ s: ScoredSentence) -> Int { count(s.text) + 1 }
        func tryAdd(_ s: ScoredSentence) -> Bool {
            var set = picked[s.chunkIndex] ?? []
            if set.contains(s.position) { return true }
            let c = cost(s)
            if used + c > tokenBudget { return false }
            set.insert(s.position)
            picked[s.chunkIndex] = set
            used += c
            return true
        }
        for s in ranked {
            let set = picked[s.chunkIndex]
            if let set, set.count >= maxSentencesPerChunk { continue }
            if set == nil {
                let titleCost = count(chunks[s.chunkIndex].title) + 1
                let first = scored.first { $0.chunkIndex == s.chunkIndex && $0.position == 0 }
                let firstCost = (openingMustFitWithMatch && first != nil && first! != s) ? cost(first!) : 0
                if used + titleCost + firstCost + cost(s) > tokenBudget { continue }
                used += titleCost
                if let first, first != s, !tryAdd(first) { used -= titleCost; continue }
            }
            _ = tryAdd(s)
        }

        func keyOrder(_ a: Int, _ b: Int) -> Bool {
            if chunkBest[a] != chunkBest[b] { return chunkBest[a] > chunkBest[b] }
            return a < b
        }
        if let top = picked.keys.sorted(by: keyOrder).first {
            let fillEnd = min(tokenBudget, used + fillMaxTokens)
            for s in scored.filter({ $0.chunkIndex == top }).sorted(by: { $0.position < $1.position }) {
                if picked[top]!.count >= maxSentencesPerChunk { break }
                if picked[top]!.contains(s.position) { continue }
                if used + cost(s) > fillEnd { continue }
                _ = tryAdd(s)
            }
        }

        let kept = picked.keys.sorted { a, b in
            let pa = pinnedIdx.contains(a) ? 1 : 0, pb = pinnedIdx.contains(b) ? 1 : 0
            if pa != pb { return pa > pb }
            return keyOrder(a, b)
        }
        let qTerms: [String] = {
            var seen = Set<String>(), out: [String] = []
            for t in tokenizeTerms(query) where seen.insert(t).inserted { out.append(t) }
            return out
        }()
        let qSet = Set(qTerms)
        // The article the question names never reads as weak (context.ts NAMED_ARTICLE_RELEVANCE).
        func shownRelevance(_ ci: Int) -> Double {
            let best = scored.filter { $0.chunkIndex == ci }.stableSorted(by: { $0.score > $1.score }).first
            let have = Set(tokenizeTerms(chunks[ci].title) + tokenizeTerms(best?.text ?? ""))
            let share = qTerms.isEmpty ? 0.0 : Double(qTerms.filter { have.contains($0) }.count) / Double(qTerms.count)
            let named = titleSep.split(chunks[ci].title).contains { seg in
                let st = tokenizeTerms(trailingParen.replace(seg, with: ""))
                return !st.isEmpty && st.allSatisfy { qSet.contains($0) }
            }
            return named ? max(share, namedArticleRelevance) : share
        }
        let out: [Chunk] = kept.map { ci in
            let body = picked[ci]!.sorted().map { p in scored.first { $0.chunkIndex == ci && $0.position == p }!.text }.joined(separator: " ")
            var c = chunks[ci]
            c.body = body
            c.relevance = (withRelevance && anyMatch) ? shownRelevance(ci) : chunks[ci].relevance
            return c
        }
        return Result(chunks: out, keptIndices: kept, tokensBefore: tokensBefore, tokensAfter: out.reduce(0) { $0 + count("\($1.title)\n\($1.body)") })
    }

    /// The passages a fast answer sends: a lookup gets 450 tokens, other questions 700.
    public static func forAnswer(_ query: String, _ chunks: [Chunk], taskType: String) -> Result {
        if chunks.isEmpty { return Result(chunks: chunks, keptIndices: [], tokensBefore: 0, tokensAfter: 0) }
        return compress(query, chunks, tokenBudget: taskType == "lookup" ? fastLookupTokens : fastOtherTokens)
    }
}
