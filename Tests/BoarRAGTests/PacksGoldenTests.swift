import BoarCore
import BoarRAG
import Foundation
import Testing

/// Format-1 pack search, source URLs and format-2 hits as chunks must match src/rag/packs.ts.
@Suite struct PacksGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.json(Fixtures.packs.appendingPathComponent("format1.json")) }

    static func source(_ key: String) -> PackSource { PackSource(rawValue: key.lowercased())! }

    @Test func format1SearchMatchesOnEveryQuestionAndLimit() throws {
        let dir = try Fixtures.tempDir("f1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try SqliteDatabase(path: Fixtures.tempCopy(of: Fixtures.packs.appendingPathComponent("format1.sqlite"), in: dir))
        defer { db.close() }
        let meta = Dictionary(uniqueKeysWithValues: try db.query("SELECT key, value FROM meta") { ($0.string(0)!, $0.string(1)!) })
        #expect(Packs.packFormat(meta, embeddingSha256: meta["embeddingModelSha256"]!) == 1)
        #expect(Packs.packFormat(meta, embeddingSha256: String(repeating: "0", count: 64)) == nil)
        var nonEmpty = 0
        let cases = try req(g["format1"]).arr
        #expect(cases.count == 168)
        for c in cases {
            let q = c["query"]!.str!
            let r = try Packs.searchFormat1(db, packId: "local-fixture", query: q, queryVec: GoldenEmbedding.hashVec(q), limit: c["limit"]!.int)
            #expect(sameChunks(r.lexical, c["lexical"]!.arr.map(goldenChunk)), "lexical \(q)")
            #expect(sameChunks(r.semantic, c["semantic"]!.arr.map(goldenChunk)), "semantic \(q)")
            if !r.lexical.isEmpty || !r.semantic.isEmpty { nonEmpty += 1 }
        }
        #expect(nonEmpty >= 20, "only \(nonEmpty) questions found anything")
    }

    @Test func format2HitsAsChunks() throws {
        let cases = try req(g["chunkCases"]).arr
        #expect(cases.count == 120)
        for c in cases {
            let o = c["hit"]!
            let h = PackHit(
                articleId: o["articleId"]!.i64, chunkId: o["chunkId"]!.i64, title: o["title"]!.str!, section: o["section"]!.str!, text: o["text"]!.str!,
                start: o["start"]!.int, end: o["end"]!.int, score: o["score"]!.dbl, via: o["via"]!.str!, source: Self.source(o["source"]!.str!),
                views: o["views"]!.i64, lead: o["lead"]!.flag, action: o["action"]!.flag, url: o["url"]?.str, license: o["license"]?.str
            )
            #expect(ChunkLine(Packs.packHitToChunk(c["packId"]!.str!, h)) == ChunkLine(goldenChunk(c["chunk"]!)))
        }
    }

    @Test func sourceURLs() throws {
        let urls = try req(g["urls"]).arr
        #expect(urls.count == 11)
        for u in urls {
            let title = u["title"]!.str!
            #expect(Packs.articleUrl(title, Self.source(u["source"]!.str!), url: u["url"]?.str) == u["out"]!.str, "\(title) \(u["url"]?.str ?? "nil")")
        }
    }

    // MARK: beyond the Kotlin test

    @Test func jsUriMatchesJavaScript() {
        #expect(JsUri.encodeURIComponent("Caf\u{00E9} (bar)/a?b=c&d") == "Caf%C3%A9%20(bar)%2Fa%3Fb%3Dc%26d")
        #expect(JsUri.encodeURI("https://x.org/wiki/Caf\u{00E9} #a") == "https://x.org/wiki/Caf%C3%A9%20#a")
        #expect(JsUri.encodeURIComponent("\u{1F417}") == "%F0%9F%90%97")
        #expect(JsUri.decodeURI("a%20b%2Fc%23d%C3%A9%f0%9f%90%97") == "a b%2Fc%23d\u{00E9}\u{1F417}")
        #expect(JsUri.decodeURI("100%") == nil)
        #expect(JsUri.decodeURI("%C3") == nil)
        #expect(JsUri.decodeURI("%C3%28") == nil)
        #expect(JsUri.decodeURI("%zz") == nil)
        #expect(Packs.normalizeUrl("https://en.wikipedia.org/wiki/Black Sea") == "https://en.wikipedia.org/wiki/Black_Sea")
        #expect(Packs.normalizeUrl("https://x.org/a b") == "https://x.org/a%20b")
        #expect(Packs.normalizeUrl("https://x.org/100%") == "https://x.org/100%")
    }

    @Test func packFormatReadsTheMeta() {
        let v1 = ["format": "boar-knowledge-pack", "embeddingModelSha256": "abc"]
        #expect(Packs.packFormat(v1, embeddingSha256: "abc") == 1)
        #expect(Packs.packFormat(v1, embeddingSha256: "xyz") == nil)
        #expect(Packs.packFormat(["format": "boar-knowledge-pack", "formatVersion": "2"], embeddingSha256: "abc") == 2)
        #expect(Packs.packFormat(["format": "other", "formatVersion": "2"], embeddingSha256: "abc") == nil)
    }
}
