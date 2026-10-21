import BoarCore
import BoarRAG
import Foundation
import Testing

/// The knowledge base on a real SQLite with FTS5.
@Suite struct KnowledgeBaseTests {
    private func vec(_ x: Float...) -> [Float] { x }
    private func kb() throws -> KnowledgeBase { try KnowledgeBase(db: SqliteDatabase.inMemory()) }

    private func seeded() throws -> KnowledgeBase {
        let kb = try kb()
        try kb.insertChunk(Chunk(chunkId: "wiki-1", docId: "season", title: "Season", body: "Seasons come from the tilt of Earth's axis toward the Sun."), embedding: vec(1, 0, 0))
        try kb.insertChunk(Chunk(chunkId: "wiki-2", docId: "monsoon", title: "Monsoon", body: "A monsoon is a seasonal change in wind and rain."), embedding: vec(0.6, 0.8, 0))
        try kb.insertChunk(Chunk(chunkId: "wiki-3", docId: "black-sea", title: "Black Sea", body: "The Black Sea is a sea between Europe and Asia."), embedding: vec(0, 0, 1))
        return kb
    }

    @Test func float32EmbeddingsRoundTripLittleEndianAsTheExpoAppStoredThem() {
        let v: [Float] = [0.25, -1.5, 3.0]
        let blob = KnowledgeBase.toBlob(v)
        #expect(Array(blob.prefix(4)) == [0, 0, 0x80, 0x3e]) // 0.25f little-endian
        #expect(KnowledgeBase.fromBlob(blob) == v)
    }

    @Test func keywordSearchNeedsEnoughOfTheQuestionsWordsAndReportsSimilarity() throws {
        let kb = try seeded()
        let hits = try kb.lexicalSearch("Why does the tilt of the axis cause seasons?", queryVec: vec(1, 0, 0), limit: 5)
        #expect(hits.map(\.chunkId) == ["wiki-1"])
        #expect(abs(hits.first!.similarity! - 1.0) <= 1e-6)
        // "black holes": one incidental word in common with "Black Sea" is not enough
        #expect(try kb.lexicalSearch("black holes", queryVec: vec(0, 0, 1), limit: 5).isEmpty)
    }

    @Test func semanticSearchKeepsOnlySimilarEnoughChunksBestFirst() throws {
        let hits = try seeded().semanticSearch(vec(1, 0.2, 0), limit: 5)
        #expect(hits.map(\.chunkId) == ["wiki-1", "wiki-2"])
        #expect(hits.allSatisfy { $0.similarity! >= RagPure.minSemanticSimilarity })
    }

    @Test func anInactiveCollectionIsNotSearchedAndDeletingItRemovesItsChunks() throws {
        let kb = try seeded()
        try kb.createCollection(id: "col1", name: "Notes", sourceFilename: "notes.txt", docCount: 1, chunkCount: 1, sizeBytes: 100, now: 1)
        try kb.insertChunk(Chunk(chunkId: "u-1", docId: "note", title: "Tilt notes", body: "My notes about axis tilt and seasons.", collectionId: "col1"), embedding: vec(1, 0, 0))
        #expect(try kb.semanticSearch(vec(1, 0, 0), limit: 5).contains { $0.chunkId == "u-1" })
        try kb.setCollectionActive("col1", false)
        #expect(try kb.semanticSearch(vec(1, 0, 0), limit: 5).allSatisfy { $0.chunkId != "u-1" })
        try kb.deleteCollection("col1")
        #expect(try kb.chunkCount() == 3)
        #expect(try kb.collections().isEmpty)
    }

    @Test func seedDeletionByPrefixNeverTouchesUserChunks() throws {
        let kb = try seeded()
        try kb.createCollection(id: "col1", name: "Notes", sourceFilename: nil, docCount: 1, chunkCount: 1, sizeBytes: 1, now: 1)
        try kb.insertChunk(Chunk(chunkId: "wiki-9", docId: "mine", title: "Mine", body: "User text.", collectionId: "col1"), embedding: vec(1, 0, 0))
        #expect(try kb.deleteSeedChunksWithPrefix("wiki-") == 3)
        #expect(try kb.chunkCount() == 1)
    }

    @Test func openingAnExistingDatabaseMigratesItWithoutLosingData() throws {
        let db = try SqliteDatabase.inMemory()
        try KnowledgeBase(db: db).insertChunk(Chunk(chunkId: "wiki-1", docId: "d", title: "T", body: "Body text here."), embedding: vec(1, 0, 0))
        #expect(try KnowledgeBase(db: db).chunkCount() == 1)
    }

    @Test func anOldDatabaseWithoutCollectionIdGainsTheColumn() throws {
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE chunks (chunk_id TEXT PRIMARY KEY, doc_id TEXT NOT NULL, title TEXT, body TEXT NOT NULL, source TEXT)")
        try db.execute("INSERT INTO chunks (chunk_id, doc_id, title, body) VALUES ('old', 'd', 'T', 'B')")
        let kb = try KnowledgeBase(db: db)
        #expect(try kb.chunkCount() == 1)
        #expect(try kb.seedChunkCount() == 1)
    }

    @Test func aCollectionExportsItsDistinctPassagesInChunkOrderAsJSONStringifyWithTwoSpaces() throws {
        let kb = try kb()
        try kb.insertChunk(Chunk(chunkId: "c1-2", docId: "d", title: "B", body: "x", collectionId: "c1"), embedding: vec(1))
        try kb.insertChunk(Chunk(chunkId: "c1-1", docId: "d", title: "Notes \"A\"", body: "line1\nline2\ttab \u{00E9} \u{1F417} \u{2028}", source: "a.md", collectionId: "c1"), embedding: vec(1))
        try kb.insertChunk(Chunk(chunkId: "c1-3", docId: "d", title: "B", body: "x", collectionId: "c1"), embedding: vec(1))
        try kb.insertChunk(Chunk(chunkId: "other", docId: "d", title: "C", body: "y", collectionId: "c2"), embedding: vec(1))
        let docs = try kb.collectionDocs("c1")
        #expect(docs.map(\.title) == ["Notes \"A\"", "B"])
        // Node: JSON.stringify([...], null, 2)
        #expect(DocumentImport.exportJson(docs) == "[\n  {\n    \"title\": \"Notes \\\"A\\\"\",\n    \"source\": \"a.md\",\n    \"body\": \"line1\\nline2\\ttab \u{00E9} \u{1F417} \u{2028}\"\n  },\n  {\n    \"title\": \"B\",\n    \"source\": \"\",\n    \"body\": \"x\"\n  }\n]")
        #expect(DocumentImport.exportJson([]) == "[]")
    }
}
