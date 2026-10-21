import BoarCore
import BoarRAG
import Foundation
import Testing

/// Full retrieval must match src/rag/retrieve.ts: a knowledge base seeded with the bundled corpus, one format-1 and three
/// format-2 packs, English and Portuguese questions (the lexicon path), the same chunks in the same order with the same
/// scores (to the last digit or two of SQLite's own bm25, see `sameChunks`).
@Suite struct RetrieverGoldenTests {
    @Test func retrievalMatchesOnEveryQuestion() async throws {
        let tmp = try Fixtures.tempDir("retrieve")
        defer { try? FileManager.default.removeItem(at: tmp) }
        func copy(_ name: String) throws -> String { try Fixtures.tempCopy(of: Fixtures.packs.appendingPathComponent(name), in: tmp) }
        let kb = try KnowledgeBase(db: SqliteDatabase(path: copy("kb.sqlite")))
        let zstd = ZstdDecoder()
        // knowledgePacks(): local pack files in name order.
        let packs: [OpenPack] = [
            .format2("local-dest", try WikiPack.open(db: SqliteDatabase(path: copy("dest.sqlite")), zstd: zstd)),
            .format1("local-fixture", try SqliteDatabase(path: copy("format1.sqlite"))),
            .format2("local-mini", try WikiPack.open(db: SqliteDatabase(path: copy("mini.sqlite")), zstd: zstd)),
            .format2("local-sources", try WikiPack.open(db: SqliteDatabase(path: copy("sources.sqlite")), zstd: zstd)),
        ]
        let lexicon = RagTextGoldenTests.lexicon
        let r = Retriever(kb: kb, packs: { packs }, embed: { GoldenEmbedding.hashVec($0) }, lexicon: { lexicon })
        let cases = try req(Fixtures.json(Fixtures.packs.appendingPathComponent("retrieve.json"))["retrieval"]).arr
        #expect(cases.count > 100)
        for c in cases {
            let q = c["query"]!.str!
            let got = try await r.retrieve(q, topK: c["topK"]!.int, queryVec: GoldenEmbedding.hashVec(q))
            #expect(sameChunks(got, c["chunks"]!.arr.map(goldenChunk)), "\(q)")
        }
    }

    // MARK: beyond the Kotlin test

    @Test func theEmbedderIsCalledWhenNoQueryVectorIsGiven() async throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        let seen = Embedded()
        let r = Retriever(kb: kb, packs: { [] }, embed: { seen.add($0); return GoldenEmbedding.hashVec($0) }, lexicon: { PtLexicon.Lexicon([:]) })
        _ = try await r.retrieve("What is a black hole?")
        #expect(seen.values == ["What is a black hole?"])
    }

    @Test func disambiguationPagesAreNeverSources() {
        #expect(Retriever.isDisambiguation(Chunk(chunkId: "a", docId: "a", title: "Mercury (disambiguation)", body: "x")))
        #expect(Retriever.isDisambiguation(Chunk(chunkId: "a", docId: "a", title: "Mercury", body: "Mercury may also refer to: the planet")))
        #expect(!Retriever.isDisambiguation(Chunk(chunkId: "a", docId: "a", title: "Mercury", body: "Mercury is the first planet.")))
    }
}
