import BoarCore
import BoarRAG
import Foundation
import Testing

/// Format-2 pack search must match src/rag/wikiPack.ts on the vitest fixture packs, built by the real builder
/// (scripts/export-native-golden-packs.mjs): stems, named articles, BM25 terms and every hit field, in order.
@Suite(.serialized) struct WikiPackGoldenTests {
    let g: JSONValue
    let helpers: JSONValue

    init() throws {
        g = try Fixtures.json(Fixtures.packs.appendingPathComponent("packs.json"))
        helpers = try req(g["helpers"])
    }

    /// Each pack opened from a private copy, so the fixture file is never written.
    static let opened = OpenedPacks()

    static func pack(_ name: String) throws -> WikiPack { try opened.pack(name) }

    /// Every field of a hit, compared exactly (scores are rounded to 2 decimals by the algorithm).
    struct HitLine: Equatable, CustomStringConvertible {
        var articleId: Int64, chunkId: Int64, title: String?, section: String?, text: String?, start: Int, end: Int, score: Double
        var via: String?, source: String?, views: Int64, lead: Bool, action: Bool, url: String?, license: String?
        init(_ h: PackHit) {
            articleId = h.articleId; chunkId = h.chunkId; title = h.title; section = h.section; text = h.text; start = h.start; end = h.end
            score = h.score; via = h.via; source = h.source.key; views = h.views; lead = h.lead; action = h.action; url = h.url; license = h.license
        }
        init(_ o: JSONValue) {
            articleId = o["articleId"]!.i64; chunkId = o["chunkId"]!.i64; title = o["title"]!.str; section = o["section"]!.str; text = o["text"]!.str
            start = o["start"]!.int; end = o["end"]!.int; score = o["score"]!.dbl; via = o["via"]!.str; source = o["source"]!.str
            views = o["views"]!.i64; lead = o["lead"]!.flag; action = o["action"]!.flag; url = o["url"]?.str; license = o["license"]?.str
        }
        var description: String {
            "\(articleId)/\(chunkId) \(title ?? "") [\(section ?? "")] \(start)-\(end) \(score) \(via ?? "") \(source ?? "") lead=\(lead) action=\(action)"
        }
    }

    @Test func stemsNamedArticlesTermsAndHitsMatchOnEveryPackAndQuestion() throws {
        var n = 0
        for c in try req(g["cases"]).arr where c["opts"] == nil {
            let p = try Self.pack(c["pack"]!.str!)
            let q = c["query"]!.str!
            let label = "[\(c["pack"]!.str!)] \(q)"
            let stems = try p.stems(q)
            let wantStems = c["stems"]!.arr
            #expect(stems.map(\.stem) == wantStems.map { $0["stem"]!.str! }, "\(label) stems")
            for (a, b) in zip(wantStems, stems) { #expect(abs(a["idf"]!.dbl - b.idf) <= 1e-9, "\(label) idf \(b.stem)") }
            let named = try p.titlesInQuestion(q, stems)
            let wantNamed = c["named"]!.arr
            #expect(named.map(\.id) == wantNamed.map { $0["id"]!.i64 }, "\(label) named")
            for (a, b) in zip(wantNamed, named) { #expect(abs(a["share"]!.dbl - b.share) <= 1e-9, "\(label) share") }
            #expect(p.queryTerms(stems) == c["terms"]!.arr.map { $0.str! }, "\(label) terms")
            #expect(try p.searchDetailed(q).hits.map(HitLine.init) == c["hits"]!.arr.map(HitLine.init), "\(label)")
            n += 1
        }
        #expect(n > 300, "only \(n) cases")
    }

    @Test func searchOptionsTitlesExpandForcedActionAndExplain() throws {
        var n = 0
        for c in try req(g["cases"]).arr where c["opts"] != nil {
            let o = c["opts"]!
            let q = c["query"]!.str!
            let expandTo = o["expandTo"]?.arr.map { $0.str! }
            let opts = PackSearchOptions(
                titles: o["titles"]?.arr.map { $0.str! } ?? [], k: o["k"]?.int ?? 6, action: o["action"]?.boolValue, explain: o["explain"]?.boolValue,
                minHits: o["minHits"]?.int ?? 2, expand: expandTo.map { list in { @Sendable _ in list } }
            )
            let got = try Self.pack(c["pack"]!.str!).searchDetailed(q, opts).hits.map(HitLine.init)
            #expect(got == c["hits"]!.arr.map(HitLine.init), "\(q) \(o)")
            n += 1
        }
        #expect(n > 0)
    }

    @Test func articlesTitleResolutionAndHeadingPaths() throws {
        let p = try Self.pack("mini")
        let a = try req(helpers["article"])
        let id = try #require(try p.resolveTitle(a["title"]!.str!))
        #expect(id == a["id"]!.i64)
        let art = try p.article(id)
        #expect(art.title == a["articleTitle"]!.str)
        #expect(art.text == a["text"]!.str)
        for s in a["sections"]!.arr { #expect(WikiPackText.sectionAt(art.text, s.arr[0].int) == s.arr[1].str) }
        for r in try req(helpers["resolve"]).arr {
            #expect(try p.resolveTitle(r.arr[0].str!) == r.arr[1].str.flatMap { Int64($0) }, "\(r.arr[0].str!)")
        }
    }

    @Test func pureHelpers() throws {
        for (q, v) in try req(helpers["titleCandidates"]).obj { #expect(WikiPackText.titleCandidates(q) == v.arr.map { $0.str! }, "\(q)") }
        for (q, v) in try req(helpers["isTravel"]).obj { #expect(WikiPackText.isTravelQuestion(q) == v.flag, "\(q)") }
        for (q, v) in try req(helpers["action"]).obj { #expect(WikiPackText.hasActionIntent(q) == v.flag, "\(q)") }
        for (t, v) in try req(helpers["instructionShare"]).obj { #expect(abs(WikiPackText.instructionShare(t) - v.dbl) <= 1e-12, "\(t)") }
        for (s, v) in try req(helpers["sectionKind"]).obj { #expect(WikiPackText.sectionKind(s) == v.str, "\(s)") }
        for (s, v) in try req(helpers["matchTerm"]).obj { #expect(WikiPackText.matchTerm(s) == v.str, "\(s)") }
    }
}

/// Fixture packs opened once from temp copies.
final class OpenedPacks: @unchecked Sendable {
    private let lock = NSLock()
    private var packs: [String: WikiPack] = [:]
    private var dir: URL?

    func pack(_ name: String) throws -> WikiPack {
        lock.lock(); defer { lock.unlock() }
        if let p = packs[name] { return p }
        if dir == nil { dir = try Fixtures.tempDir("packs") }
        let path = try Fixtures.tempCopy(of: Fixtures.packs.appendingPathComponent("\(name).sqlite"), in: dir!)
        let p = try WikiPack.open(db: SqliteDatabase(path: path), zstd: ZstdDecoder())
        packs[name] = p
        return p
    }
}
