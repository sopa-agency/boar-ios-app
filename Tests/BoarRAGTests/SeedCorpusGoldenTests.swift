import BoarCore
import BoarRAG
import Foundation
import Testing

/// Seeding must index exactly what src/rag/seedCorpus.ts does (scripts/export-native-golden-seed.mjs): same chunk ids,
/// rows, order and embedding inputs, the retired chunk removed, and nothing re-embedded on a second run.
@Suite struct SeedCorpusGoldenTests {
    @Test func sameChunksAsTheExpoAppAndASecondRunEmbedsNothing() async throws {
        let g = try Fixtures.golden("seed.json")
        let db = try SqliteDatabase.inMemory()
        let kb = try KnowledgeBase(db: db)
        try kb.insertChunk(Chunk(chunkId: "app-grapheneos", docId: "app-grapheneos", title: "GrapheneOS", body: "old"), embedding: [1, 0])
        let embedded = Embedded()
        let seed = SeedCorpus(kb: kb, embed: { text in
            embedded.add(text)
            return [Float(text.utf16.count), 1, 0, 0]
        })
        let collections = [
            SeedCorpus.Collection(id: SeedCorpus.builtin, docs: try SeedCorpus.docs(collectionId: SeedCorpus.builtin, json: Fixtures.text(Fixtures.asset("corpus/corpus.json")))),
            SeedCorpus.Collection(id: "corpus-standard", docs: try SeedCorpus.docs(collectionId: "corpus-standard", json: Fixtures.text(Fixtures.asset("corpus/corpus-standard.json")))),
        ]
        #expect(try await seed.seed(collections) == g["embedded"]!.arr.count)
        let rows = try db.query("SELECT chunk_id, doc_id, title, body, source FROM chunks ORDER BY rowid") { r in (0...4).map { r.string($0) } }
        let want: [[String?]] = g["rows"]!.arr.map { e in ["chunk_id", "doc_id", "title", "body", "source"].map { e[$0]!.str } }
        #expect(rows.map { $0[0] } == want.map { $0[0] })
        #expect(rows == want)
        #expect(embedded.values == g["embedded"]!.arr.map { $0.str! })
        #expect(try await seed.seed(collections) == g["secondRunEmbedded"]!.int)
    }

    // MARK: beyond the Kotlin test

    @Test func theFirstDocumentWithASlugWinsAndTheBuiltinPrefixIsMin() throws {
        let docs = try SeedCorpus.docs(collectionId: SeedCorpus.builtin, json: #"[{"title":"Black Sea","source":"s1","body":"one"},{"title":"black sea!","source":"s2","body":"two"},{"title":"Moon","body":"m"}]"#)
        #expect(docs.map(\.id) == ["wiki-min-black-sea", "wiki-min-moon"])
        #expect(docs.map(\.body) == ["one", "m"])
        #expect(docs.map(\.source) == ["s1", ""])
        #expect(SeedCorpus.chunkIdPrefix("corpus-standard") == "wiki-corpus-standard-")
    }

    @Test func stoppingThrowsAndCollectionsWithAnErrorAreSkipped() async throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        let seed = SeedCorpus(kb: kb, embed: { _ in [1] })
        let doc = SeedCorpus.Doc(id: "wiki-x-a", title: "A", source: "", body: "b")
        await #expect(throws: SeedCorpus.Stopped.self) { _ = try await seed.seed([.init(id: "x", docs: [doc])], shouldStop: { true }) }
        #expect(try await seed.seed([.init(id: "x", docs: [doc], error: "download failed")]) == 0)
        #expect(try await seed.seed([.init(id: "x", docs: [doc])]) == 1)
    }
}
