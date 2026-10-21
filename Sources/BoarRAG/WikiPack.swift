import BoarCore
import Foundation

/// Search over a large knowledge pack (format 2, built by scripts/build-wiki-pack.mjs): Wikipedia, Wikivoyage and
/// other sources' text in zstd blocks, a contentless FTS5 index, redirects and per-article popularity. Port of
/// src/rag/wikiPack.ts; outputs match it (golden tests).
///
/// The retrieval design is derived from AndroidLM's Corpus.kt / rag.py (https://github.com/Phineas1500/AndroidLM,
/// Apache-2.0; see android-native/NOTICE): rarest-first query stems with a df cut, whole-index BM25 with a title-column
/// weight and a popularity prior, titles resolved through redirects, and per-article passages (lead + best sections).
/// BOAR's additions: title candidates taken from the question itself, action/explain/travel handling, lay sources.
///
/// Calls are synchronous (SQLite) and serialized per pack; run them off the main actor.
public final class WikiPack: @unchecked Sendable {
    private let db: any SqlDatabase
    private let zstd: any Zstd
    public let meta: [String: String]
    private let nIndexed: Double
    private let hasRedirects: Bool
    private let hasDf: Bool
    private let hasMeta: Bool
    /// Sources besides Wikipedia and Wikivoyage in a multi-source pack: their titles count as names too.
    private let topicSources: [PackSource]

    private let lock = NSRecursiveLock()
    private var _tuning = PackTuning()
    private var blocks = FifoCache<Int64, Data>(max: 16)
    private var articles = FifoCache<Int64, PackArticle>(max: 16)
    private var resolved = FifoCache<String, ResolvedId>(max: 512)

    private struct ResolvedId { var id: Int64? }

    public struct Result: Sendable, Equatable {
        public var hits: [PackHit]
        public var stems: [Stem]
    }

    public struct Named: Sendable, Equatable {
        public var id: Int64
        public var share: Double
    }

    public struct PackError: Error, CustomStringConvertible {
        public var description: String
    }

    private init(
        db: any SqlDatabase, zstd: any Zstd, meta: [String: String], nIndexed: Double, hasRedirects: Bool, hasDf: Bool, hasMeta: Bool,
        topicSources: [PackSource]
    ) {
        self.db = db; self.zstd = zstd; self.meta = meta; self.nIndexed = nIndexed
        self.hasRedirects = hasRedirects; self.hasDf = hasDf; self.hasMeta = hasMeta; self.topicSources = topicSources
    }

    public var tuning: PackTuning {
        get { lock.withLock { _tuning } }
        set { lock.withLock { _tuning = newValue } }
    }

    private static let words = Rx("[\\p{L}\\p{N}]+")

    /// [stem, idf] for the content words of `text`, stemmed by FTS5 itself.
    public func stems(_ text: String) throws -> [Stem] {
        try lock.withLock {
            let ws = Self.words.all(text.lowercased()).map(\.value).filter { $0.u16Count > 1 && !WikiPackText.stopwords.contains($0) }
            if ws.isEmpty { return [] }
            try db.execute("DELETE FROM temp.qtok")
            try db.execute("INSERT INTO temp.qtok (x) VALUES (?)", args: [.text(ws.joined(separator: " "))])
            let terms = try db.query("SELECT term FROM temp.qtok_v") { $0.string(0)! }
            var out: [Stem] = []
            for term in terms {
                var doc: Int64? = nil
                if hasDf { doc = try db.query("SELECT doc FROM df WHERE term = ?", args: [.text(term)]) { $0.long(0) }.first }
                if doc == nil { doc = try db.query("SELECT doc FROM temp.fts_v WHERE term = ?", args: [.text(term)]) { $0.long(0) }.first }
                if let doc, doc > 0 { out.append(Stem(stem: term, idf: log(nIndexed / Double(doc)))) }
            }
            return out
        }
    }

    /// Rarest-first stems, dropping those in more than `maxDf` of chunks while `keepMin` rarer ones remain.
    public func queryTerms(_ stems: [Stem], maxDf: Double = 0.02, keepMin: Int = 3) -> [String] {
        let ranked = stems.stableSorted { $0.idf > $1.idf }
        let kept = ranked.filter { $0.idf >= log(1 / maxDf) }.map(\.stem)
        return kept.count >= keepMin ? kept : ranked.prefix(keepMin).map(\.stem)
    }

    private func block(_ id: Int64) throws -> Data {
        if let b = blocks[id] { return b }
        guard let z = try db.query("SELECT zdata FROM blocks WHERE id = ?", args: [.integer(id)], map: { $0.blob(0)! }).first else {
            throw PackError(description: "pack block \(id) missing")
        }
        let d = try zstd.decompress(z)
        blocks[id] = d
        return d
    }

    public func article(_ id: Int64) throws -> PackArticle {
        try lock.withLock {
            if let a = articles[id] { return a }
            struct Row { var title: String; var source: Int; var views: Int64; var blockId: Int64; var off: Int; var len: Int }
            guard let a = try db.query(
                "SELECT title, source, views, block_id, off, len FROM articles WHERE id = ?", args: [.integer(id)],
                map: { Row(title: $0.string(0)!, source: $0.int(1), views: $0.long(2), blockId: $0.long(3), off: $0.int(4), len: $0.int(5)) }
            ).first else { throw PackError(description: "pack article \(id) missing") }
            let blockData = try block(a.blockId)
            guard a.off >= 0, a.len >= 0, a.off + a.len <= blockData.count else { throw PackError(description: "pack article \(id) is outside its block") }
            let text = String(decoding: blockData.subdata(in: (blockData.startIndex + a.off)..<(blockData.startIndex + a.off + a.len)), as: UTF8.self)
            var url: String? = nil, license: String? = nil
            if hasMeta, let m = try db.query("SELECT url, license FROM article_meta WHERE article_id = ?", args: [.integer(id)], map: { ($0.string(0), $0.string(1)) }).first {
                url = (m.0?.isEmpty ?? true) ? nil : m.0
                license = (m.1?.isEmpty ?? true) ? nil : m.1
            }
            let art = PackArticle(
                id: id, title: a.title, source: Self.sources.indices.contains(a.source) ? Self.sources[a.source] : .enwiki, views: a.views,
                text: text, url: url, license: license
            )
            articles[id] = art
            return art
        }
    }

    /// Article id for a title: exact (case-insensitive), then redirects, then (fuzzy) a title search.
    public func resolveTitle(_ title: String, fuzzy: Bool = true, source: PackSource = .enwiki) throws -> Int64? {
        try lock.withLock {
            let key = "\(fuzzy ? "f" : "x"):\(source.key):\(title)"
            if let r = resolved[key] { return r.id }
            let src = Int64(Self.sources.firstIndex(of: source) ?? -1)
            var id = try db.query(
                "SELECT id FROM articles WHERE title = ? COLLATE NOCASE AND source = ? ORDER BY views DESC LIMIT 1",
                args: [.text(title), .integer(src)], map: { $0.long(0) }
            ).first
            if id == nil && hasRedirects {
                id = try db.query(
                    "SELECT r.article_id FROM redirects r JOIN articles a ON a.id = r.article_id WHERE r.title = ? AND a.source = ? ORDER BY a.views DESC LIMIT 1",
                    args: [.text(title), .integer(src)], map: { $0.long(0) }
                ).first
            }
            let ws = Self.words.all(title.lowercased()).map(\.value)
            if id == nil && fuzzy && ws.count >= 2 {
                let match = "title:(\(ws.map { "\"\($0)\"" }.joined(separator: " AND ")))"
                let rows = try db.query(
                    """
                    SELECT a.id, a.title, a.views FROM (SELECT rowid FROM fts WHERE fts MATCH ? ORDER BY bm25(fts, 8.0, 0.0, 0.0) LIMIT 30) f
                    JOIN chunks c ON c.id = f.rowid JOIN articles a ON a.id = c.article_id WHERE a.source = ?
                    """,
                    args: [.text(match), .integer(src)], map: { ($0.long(0), $0.string(1)!, $0.long(2)) }
                )
                var best = -Double.infinity
                for (rid, rtitle, views) in rows {
                    let extra = max(0, Self.words.all(rtitle).count - ws.count)
                    if extra > 1 { continue }
                    let k = log10(10.0 + Double(views)) - 0.5 * Double(extra)
                    if k > best { best = k; id = rid }
                }
            }
            resolved[key] = ResolvedId(id: id)
            return id
        }
    }

    /// BM25-like score of a passage, 0..1; question terms in the heading count double.
    private func passageScore(_ text: String, _ start: Int, _ end: Int, _ stems: [Stem]) -> Double {
        let body = text.u16Sub(start, end).lowercased()
        let heading = WikiPackText.sectionAt(text, start).lowercased()
        var total = stems.reduce(0.0) { $0 + $1.idf }
        if total == 0.0 { total = 1.0 }
        var score = 0.0
        for s in stems {
            let p = WikiPackText.prefixOf(s.stem)
            let tf = Double(WikiPackText.countAtBoundary(p, body) + 2 * WikiPackText.countAtBoundary(p, heading))
            score += (s.idf * tf) / (tf + 1.5)
        }
        return score / total
    }

    private func hit(_ articleId: Int64, _ chunkId: Int64, _ start: Int, _ end: Int, _ score: Double, _ via: String, lead: Bool = false) throws -> PackHit {
        let a = try article(articleId)
        let section = WikiPackText.sectionAt(a.text, start)
        let slice = a.text.u16Sub(start, end)
        return PackHit(
            articleId: articleId, chunkId: chunkId, title: a.title, section: section, text: Js.trim(slice), start: start, end: end,
            score: WikiPackText.jsRound2(score), via: via, source: a.source, views: a.views, lead: lead,
            action: !lead && WikiPackText.isActionPassage(section, slice), url: a.url, license: a.license
        )
    }

    private struct Scored: Equatable { var id: Int64; var start: Int; var end: Int; var s: Double; var sec: String }

    /// The article's lead chunk plus its `nSections` chunks that best cover the question.
    public func articlePassages(_ articleId: Int64, _ stems: [Stem], nSections: Int = 2, action: Bool = false, explain: Bool = false) throws -> [PackHit] {
        try lock.withLock {
            let a = try article(articleId)
            struct Row { var id: Int64; var start: Int; var end: Int }
            let rows = try db.query("SELECT id, start, end FROM chunks WHERE article_id = ? ORDER BY id", args: [.integer(articleId)]) {
                Row(id: $0.long(0), start: $0.int(1), end: $0.int(2))
            }
            if rows.isEmpty { return [] }
            let leadIndex = (a.text.u16StartsWith("Key facts:", at: rows[0].start) && rows.count > 1) ? 1 : 0
            let lead = rows[leadIndex]
            var seenSec = Set<String>()
            let scoredAll: [Scored] = rows.enumerated().filter { $0.offset != leadIndex }.map { (_, r) in
                let sec = WikiPackText.sectionAt(a.text, r.start)
                let s = passageScore(a.text, r.start, r.end, stems)
                if !action { return Scored(id: r.id, start: r.start, end: r.end, s: s, sec: sec) }
                let kind = WikiPackText.sectionKind(sec)
                if kind == "background" { return Scored(id: r.id, start: r.start, end: r.end, s: s * 0.3, sec: sec) }
                let share = WikiPackText.instructionShare(a.text.u16Sub(r.start, r.end))
                if kind == "other" { return Scored(id: r.id, start: r.start, end: r.end, s: share >= 0.35 ? s + 0.5 + 0.4 * share : s, sec: sec) }
                return Scored(id: r.id, start: r.start, end: r.end, s: s + (kind == "action" ? 0.5 : 0.25) + 0.4 * share, sec: sec)
            }
            let scored = scoredAll.stableSorted { $0.s != $1.s ? $0.s > $1.s : $0.start > $1.start }.filter { seenSec.insert($0.sec).inserted }
            let ordered = action ? WikiPackText.stepsFirst(scored, score: { $0.s }, sectionOf: { $0.sec }) : scored
            let picked = ordered.prefix(max(0, nSections)).filter { $0.s > 0.15 }
            func leadHit() throws -> PackHit { try hit(articleId, lead.id, lead.start, lead.end, 1.0, "title", lead: true) }
            if explain {
                let titleLow = a.title.lowercased()
                let beyond = stems.filter { WikiPackText.countAtBoundary(WikiPackText.prefixOf($0.stem), titleLow, firstOnly: true) == 0 }
                func cover(_ start: Int, _ end: Int) -> Int {
                    let low = a.text.u16Sub(start, end).lowercased()
                    return beyond.filter { WikiPackText.countAtBoundary(WikiPackText.prefixOf($0.stem), low, firstOnly: true) > 0 }.count
                }
                if let best = picked.stableSorted(by: { cover($0.start, $0.end) > cover($1.start, $1.end) }).first,
                   cover(best.start, best.end) > cover(lead.start, lead.end) {
                    var out = [try hit(articleId, best.id, best.start, best.end, best.s, "title"), try leadHit()]
                    for p in picked where p != best { out.append(try hit(articleId, p.id, p.start, p.end, p.s, "title")) }
                    return out
                }
            }
            var out = [try leadHit()]
            for p in picked { out.append(try hit(articleId, p.id, p.start, p.end, p.s, "title")) }
            return out
        }
    }

    /// bm25()'s ranking without reading article text; at most `perArticle` per article.
    public func bm25Candidates(_ stems: [Stem], pool: Int? = nil, prior: Double? = nil, perArticle: Int = 2) throws -> [Candidate] {
        try lock.withLock {
            let tuning = _tuning
            let pool = pool ?? tuning.pool, prior = prior ?? tuning.prior
            let terms = queryTerms(stems)
            if terms.isEmpty { return [] }
            let w = tuning.weights.map(Self.jsNumber).joined(separator: ", ")
            let rows = try db.query(
                """
                SELECT f.rowid AS id, f.s, c.article_id, c.start, c.end, a.views
                FROM (SELECT rowid, bm25(fts, \(w)) AS s FROM fts WHERE fts MATCH ? ORDER BY s LIMIT ?) f
                JOIN chunks c ON c.id = f.rowid JOIN articles a ON a.id = c.article_id
                """,
                args: [.text(terms.map(WikiPackText.matchTerm).joined(separator: " OR ")), .integer(Int64(pool))]
            ) {
                Candidate(chunkId: $0.long(0), articleId: $0.long(2), start: $0.int(3), end: $0.int(4), score: -$0.double(1) + prior * log10(1.0 + Double($0.long(5))))
            }
            let sorted = rows.stableSorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.articleId != b.articleId { return a.articleId > b.articleId }
                return a.start > b.start
            }
            var per: [Int64: Int] = [:]
            return sorted.filter { c in
                let n = per[c.articleId] ?? 0
                per[c.articleId] = n + 1
                return n < perArticle
            }
        }
    }

    public func bm25(_ stems: [Stem]) throws -> [PackHit] { try bm25Candidates(stems).map(materialize) }

    private func materialize(_ c: Candidate) throws -> PackHit { try hit(c.articleId, c.chunkId, c.start, c.end, c.score, "bm25") }

    private static let disambig = Rx("(?i)\\(disambiguation\\)\\z")
    private static let upperStart = Rx("^\\p{Lu}")
    private static let regionBefore = Rx("\\p{Lu}[\\p{L}\\p{N}.'\u{2019}-]*,\(Js.ws)*\\z")
    private static let regionAfter = Rx("^,\(Js.ws)*(\\p{Lu}[\\p{L}.'\u{2019}-]*(?:\(Js.ws)+\\p{Lu}[\\p{L}.'\u{2019}-]*){0,3})")
    private static let wsRun = Rx("\(Js.ws)+")

    private func isDisambiguationPage(_ id: Int64) throws -> Bool {
        guard let t = try db.query("SELECT title FROM articles WHERE id = ?", args: [.integer(id)], map: { $0.string(0) }).first, let title = t else { return false }
        return Self.disambig.contains(title)
    }

    private func isRare(_ word: String, _ rare: Set<String>) throws -> Bool {
        try stems(word).first.map { rare.contains($0.stem) } ?? false
    }

    /// Articles the question names (its longest n-grams that are titles or redirects), with their share of its weight.
    public func titlesInQuestion(_ query: String, _ stems: [Stem], max maxNames: Int = 4) throws -> [Named] {
        try lock.withLock {
            let rare = Set(stems.filter { $0.idf >= log(1 / 0.002) }.map(\.stem))
            let content = stems.filter { !WikiPackText.foreignFunctionWords.contains($0.stem) && !WikiPackText.actionWords.contains($0.stem) }
            var weight: [String: Double] = [:]
            for s in content { weight[s.stem] = s.idf }
            var total = content.reduce(0.0) { $0 + $1.idf }
            if total == 0.0 { total = 1.0 }
            let sources: [PackSource] = (WikiPackText.travelIntent.contains(query) ? [.enwikivoyage, .enwiki] : [.enwiki, .enwikivoyage]) + topicSources
            var found: [Named] = []
            var used: [String] = []
            let travel = WikiPackText.isTravelQuestion(query)
            let opening = (Self.words.find(query)?.value ?? "").lowercased()
            var unresolvedNames: [[String]] = []
            let destination = travel ? try destinationOf(query, opening) : nil
            for cand in WikiPackText.titleCandidates(query) {
                if used.count >= maxNames { break }
                let lower = cand.lowercased()
                if used.contains(where: { $0.contains(lower) }) { continue }
                let single = !cand.contains(" ")
                if single && lower == opening && WikiPackText.questionWords.contains(lower) { continue }
                if single && !Self.upperStart.contains(cand) {
                    let notRare = !(try isRare(lower, rare))
                    if notRare, !(try self.stems(lower)).isEmpty { continue }
                }
                if single && unresolvedNames.contains(where: { $0.contains(lower) }) { continue }
                var ids: [(Int64, Bool)] = []
                for source in sources {
                    let sing = WikiPackText.singularTitle(cand)
                    var id = try resolveTitle(cand, fuzzy: false, source: source)
                    if id == nil, let sing { id = try resolveTitle(sing, fuzzy: false, source: source) }
                    if let id, try isDisambiguationPage(id) { continue }
                    if let id, !found.contains(where: { $0.id == id }) { ids.append((id, topicSources.contains(source))) }
                }
                if ids.isEmpty {
                    let ws = Self.wsRun.split(lower)
                    if ws.count > 1 && Self.wsRun.split(cand).allSatisfy({ Self.upperStart.contains($0) }) { unresolvedNames.append(ws) }
                    continue
                }
                let own = try self.stems(cand)
                let wordSet = Set(Self.words.all(lower).map(\.value).filter { $0.u16Count > 1 && !WikiPackText.stopwords.contains($0) })
                let share = own.count < wordSet.count ? 1.0 : own.reduce(0.0) { $0 + (weight[$1.stem] ?? 0.0) } / total
                for (id, primary) in ids { found.append(Named(id: id, share: primary ? 1.0 : share)) }
                used.append(lower)
            }
            if let destination {
                if let at = found.firstIndex(where: { $0.id == destination }) { found.remove(at: at) }
                found.insert(Named(id: destination, share: 1.0), at: 0)
            }
            return found
        }
    }

    /// The destination of a travel question: the first place, after a place cue, that is a Wikivoyage guide.
    private func destinationOf(_ query: String, _ opening: String) throws -> Int64? {
        func at(_ c: String) -> Int {
            let rx = Rx("(^|[^\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: c))(?![\\p{L}\\p{N}])")
            guard let m = rx.find(query) else { return -1 }
            return m.start + (m.group(1) ?? "").u16Count
        }
        struct Cand { var text: String; var pos: Int }
        let placed: [Cand] = WikiPackText.titleCandidates(query).filter { Self.upperStart.contains($0) }
            .map { Cand(text: $0, pos: at($0)) }.filter { $0.pos >= 0 }
        let cands: [Cand] = placed.stableSorted { (a: Cand, b: Cand) -> Bool in
            if a.pos != b.pos { return a.pos < b.pos }
            return a.text.u16Count > b.text.u16Count
        }
        var unresolved: [(Int, Int)] = []
        for cand in cands {
            let c = cand.text, pos = cand.pos
            let end = pos + c.u16Count
            if unresolved.contains(where: { pos >= $0.0 && end <= $0.1 }) { continue }
            let single = !c.contains(" ")
            let lower = c.lowercased()
            if single && lower == opening && WikiPackText.questionWords.contains(lower) { continue }
            let before = query.u16Sub(0, pos)
            if WikiPackText.originCue.contains(before) || !WikiPackText.placeCue.contains(before) { continue }
            if Self.regionBefore.contains(before) { continue }
            let region = Self.regionAfter.find(query.u16Sub(from: end))?.group(1)
            var id: Int64? = nil
            if let region { id = try resolveTitle("\(c) (\(region))", fuzzy: false, source: .enwikivoyage) }
            if id == nil { id = try resolveTitle(c, fuzzy: false, source: .enwikivoyage) }
            guard let found = id else {
                if !single && Self.wsRun.split(c).allSatisfy({ Self.upperStart.contains($0) }) { unresolved.append((pos, end)) }
                continue
            }
            if try isDisambiguationPage(found) { continue }
            return found
        }
        return nil
    }

    public func search(_ query: String, _ opts: PackSearchOptions = PackSearchOptions()) throws -> [PackHit] { try searchDetailed(query, opts).hits }

    /// Named articles first (lead + best sections, round-robin), then BM25 hits covering at least half the topic.
    public func searchDetailed(_ query: String, _ opts: PackSearchOptions = PackSearchOptions()) throws -> Result {
        try lock.withLock {
            let stems = try self.stems(query)
            let tuning = _tuning
            var ids = try titlesInQuestion(query, stems).filter { $0.share >= tuning.namedMinShare }.map(\.id)
            for t in opts.titles {
                if let id = try resolveTitle(t), !ids.contains(id) { ids.append(id) }
            }
            let action = opts.action ?? WikiPackText.hasActionIntent(query)
            var lay = 0
            var hits = try titleHits(ids, stems, 5, action, opts.explain ?? Explain.hasExplainIntent(query))
            let limit = max(opts.k, ids.count * 2)
            let topic = opts.titles.isEmpty ? stems : try self.stems(opts.titles.joined(separator: " "))
            let topicOrStems = topic.isEmpty ? stems : topic
            var seen = Set(hits.map(\.chunkId))
            var keyword: [Candidate]? = nil
            if hits.count < limit {
                var kw = try bm25Candidates(stems)
                let sem = try opts.queryVec.map { try leadSimilarity(kw.map(\.articleId), $0) }
                let w = tuning.semanticWeight
                if let sem, !sem.isEmpty, w > 0, !kw.isEmpty {
                    let known = sem.values.sorted()
                    let median = known[known.count / 2]
                    let maxScore = Swift.max(kw.map(\.score).max()!, 1e-9)
                    func blended(_ c: Candidate) -> Double { (1 - w) * (c.score / maxScore) + w * (sem[c.articleId] ?? median) }
                    kw = kw.stableSorted { blended($0) > blended($1) }
                }
                keyword = kw
                for c in kw {
                    if hits.count >= limit { break }
                    if seen.contains(c.chunkId) { continue }
                    let h = try materialize(c)
                    let relevant = WikiPackText.coverage("\(h.title) \(h.text)", topicOrStems) >= 0.5 || (sem?[c.articleId] ?? 0.0) >= WikiPackText.semanticKeep
                    let perArticle = hits.filter { $0.articleId == c.articleId }.count
                    if action && perArticle >= 3 { continue }
                    if relevant && !hits.contains(where: { WikiPackText.nearDuplicate($0.text, h.text) }) {
                        if action {
                            let acts = try articlePassages(c.articleId, stems, nSections: 3, action: true).filter { $0.action && !seen.contains($0.chunkId) }
                            if !acts.isEmpty && acts[0].chunkId != h.chunkId {
                                for act in acts.prefix(max(0, 3 - perArticle)) {
                                    var a = act
                                    a.via = "bm25"; a.score = h.score
                                    hits.append(a)
                                    seen.insert(act.chunkId)
                                }
                                continue
                            }
                        }
                        hits.append(h)
                        seen.insert(c.chunkId)
                    }
                }
            }
            if action {
                let pool = try keyword ?? bm25Candidates(stems)
                if !hits.contains(where: { $0.source == .usgov }) {
                    for c in pool {
                        if seen.contains(c.chunkId) { continue }
                        let h = try materialize(c)
                        if h.source != .usgov || WikiPackText.coverage("\(h.title) \(h.text)", topicOrStems) < 0.5 { continue }
                        let acts = Array(try articlePassages(c.articleId, stems, nSections: 3, action: true).filter { $0.action && !seen.contains($0.chunkId) }.prefix(2))
                        if acts.isEmpty { continue }
                        hits.insert(contentsOf: acts.map { var a = $0; a.via = "bm25"; return a }, at: min(1, hits.count))
                        for a in acts { seen.insert(a.chunkId) }
                        lay += acts.count
                        break
                    }
                }
                if !hits.contains(where: { WikiPackText.laySources.contains($0.source) }) {
                    for c in pool {
                        if lay >= 2 { break }
                        if seen.contains(c.chunkId) { continue }
                        let h = try materialize(c)
                        if !WikiPackText.laySources.contains(h.source) || WikiPackText.coverage("\(h.title) \(h.text)", topicOrStems) < 0.5 { continue }
                        if hits.contains(where: { WikiPackText.nearDuplicate($0.text, h.text) }) { continue }
                        hits.append(h)
                        seen.insert(c.chunkId)
                        lay += 1
                    }
                }
            }
            var result = hits
            if hits.count < opts.minHits, let expand = opts.expand {
                let extra = expand(query).filter { !Js.trim($0).isEmpty }
                if !extra.isEmpty {
                    let more = try search("\(query) \(extra.joined(separator: " "))", PackSearchOptions(titles: opts.titles + extra, k: opts.k))
                    let have = Set(hits.map(\.chunkId))
                    result = hits + more.filter { !have.contains($0.chunkId) }
                }
            }
            return Result(hits: Array(result.prefix(max(0, limit + lay))), stems: stems)
        }
    }

    private func titleHits(_ ids: [Int64], _ stems: [Stem], _ ranks: Int, _ action: Bool, _ explain: Bool) throws -> [PackHit] {
        let perTitle = try ids.map { try articlePassages($0, stems, nSections: 2, action: action, explain: !action && explain) }
        var hits: [PackHit] = []
        var seen = Set<Int64>()
        func add(_ h: PackHit) { if seen.insert(h.chunkId).inserted { hits.append(h) } }
        perTitle.first?.prefix(2).forEach(add)
        for r in 0..<ranks { for p in perTitle where r < p.count { add(p[r]) } }
        return hits
    }

    /// Cosine of each article's lead embedding to the question (articles without one are left out).
    public func leadSimilarity(_ ids: [Int64], _ queryVec: [Float]) throws -> [Int64: Double] {
        var seen = Set<Int64>(), distinct: [Int64] = []
        for i in ids where seen.insert(i).inserted { distinct.append(i) }
        return try leadVectors(distinct).mapValues { RagPure.cosineInt8(queryVec, $0) }
    }

    public func leadVectors(_ ids: [Int64]) throws -> [Int64: Data] {
        if ids.isEmpty { return [:] }
        let rows = try? lock.withLock {
            try db.query(
                "SELECT article_id, vec FROM lead_vecs WHERE article_id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                args: ids.map { SqlValue.integer($0) }, map: { ($0.long(0), $0.blob(1)!) }
            )
        }
        var out: [Int64: Data] = [:]
        for (k, v) in rows ?? [] { out[k] = v }
        return out
    }

    /// Closes the pack's database (after a pack is removed or replaced).
    public func close() { db.close() }

    /// Index = articles.source code written by scripts/build-wiki-pack.mjs.
    static let sources: [PackSource] = [.enwiki, .enwikivoyage, .enwikibooks, .appropedia, .usgov, .eips, .ethspecs, .ethereumorg, .bips]

    public static func open(db: any SqlDatabase, zstd: any Zstd) throws -> WikiPack {
        let meta = Dictionary(
            try db.query("SELECT key, value FROM meta") { ($0.string(0)!, $0.string(1) ?? "") }, uniquingKeysWith: { $1 }
        )
        if meta["format"] != "boar-knowledge-pack" || meta["formatVersion"] != "2" { throw PackError(description: "not a format-2 knowledge pack") }
        try db.exec(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS temp.fts_v USING fts5vocab(main, fts, row);
            CREATE VIRTUAL TABLE IF NOT EXISTS temp.qtok USING fts5(x, tokenize='porter unicode61 remove_diacritics 2');
            CREATE VIRTUAL TABLE IF NOT EXISTS temp.qtok_v USING fts5vocab(temp, qtok, row);
            """
        )
        let tables = Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'") { $0.string(0)! })
        var topicSources: [PackSource] = []
        if tables.contains("article_meta") {
            topicSources = try db.query("SELECT DISTINCT source FROM articles") { $0.int(0) }
                .compactMap { sources.indices.contains($0) ? sources[$0] : nil }.filter { $0 != .enwiki && $0 != .enwikivoyage }
        }
        var indexed = 1.0
        if let s = meta["indexedChunks"], let d = Double(s), d != 0.0, !d.isNaN { indexed = d }
        return WikiPack(
            db: db, zstd: zstd, meta: meta, nIndexed: indexed, hasRedirects: tables.contains("redirects"), hasDf: tables.contains("df"),
            hasMeta: tables.contains("article_meta"), topicSources: topicSources
        )
    }

    /// JavaScript's Number → string for the bm25 weights (2 → "2", 1.5 → "1.5").
    private static func jsNumber(_ x: Double) -> String { x == x.rounded(.down) && abs(x) < 1e15 ? String(Int64(x)) : "\(x)" }
}

/// A small insertion-ordered cache (Kotlin's LinkedHashMap with removeEldestEntry): the oldest insertion goes first.
struct FifoCache<K: Hashable, V> {
    let max: Int
    private var map: [K: V] = [:]
    private var order: [K] = []

    init(max: Int) { self.max = max }

    subscript(key: K) -> V? {
        get { map[key] }
        set {
            if let newValue {
                if map.updateValue(newValue, forKey: key) == nil {
                    order.append(key)
                    if order.count > max { map.removeValue(forKey: order.removeFirst()) }
                }
            } else if map.removeValue(forKey: key) != nil {
                order.removeAll { $0 == key }
            }
        }
    }
}
