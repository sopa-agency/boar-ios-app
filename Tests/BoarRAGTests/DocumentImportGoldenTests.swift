import BoarCore
import BoarRAG
import Foundation
import Testing

/// Document import must make the same collection and chunks as importDocuments (scripts/export-native-golden-import.mjs).
@Suite struct DocumentImportGoldenTests {
    @Test func sameCollectionChunksAndEmbeddingInputsAsTheTS() async throws {
        let runs = try Fixtures.golden("import.json").arr
        #expect(runs.count == 2)
        for run in runs {
            let col = run["collection"]!
            let id = col["id"]!.str!
            let name = run["name"]!.str!
            let files = run["files"]!.arr.map { DocumentImport.File(name: $0["name"]!.str!, sizeBytes: $0["size"]!.i64, text: $0["text"]!.str!) }
            let db = try SqliteDatabase.inMemory()
            let kb = try KnowledgeBase(db: db)
            let embedded = Embedded()
            _ = try await DocumentImport.importDocuments(kb: kb, embed: { t in embedded.add(t); return [1] }, files: files, collectionName: name, collectionId: id)
            // The collection id itself comes from the name and the time (collectionId), checked separately below.
            let made = try kb.collections()
            #expect(made.count == 1)
            let m = try #require(made.first)
            #expect(m.name == col["name"]!.str)
            #expect(m.sourceFilename == col["sourceFilename"]!.str)
            #expect(m.docCount == col["docCount"]!.i64)
            #expect(m.chunkCount == col["chunkCount"]!.i64)
            #expect(m.sizeBytes == col["sizeBytes"]!.i64)
            let rows = try db.query("SELECT chunk_id, doc_id, title, body, source, collection_id FROM chunks ORDER BY rowid") { r in (0...5).map { r.string($0) } }
            let want: [[String?]] = run["chunks"]!.arr.map { c in ["chunkId", "docId", "title", "body", "source"].map { c[$0]!.str } + [id] }
            #expect(rows == want, "\(name)")
            #expect(embedded.values == run["embedded"]!.arr.map { $0.str! }, "\(name)")
            // collectionId: "custom-<ms>-<slug of the name>"
            let ms = Int64(id.dropFirst("custom-".count).split(separator: "-", maxSplits: 1)[0])!
            #expect(DocumentImport.collectionId(name, nowMs: ms) == id)
        }
    }

    // MARK: beyond the Kotlin test

    @Test func parseHandlesJsonCsvAndLimits() throws {
        let docs = try DocumentImport.parse(.init(name: "set.json", sizeBytes: 10, text: #"[{"title":"A","body":"x","source":"s"},{"title":"B","body":"y"}]"#))
        #expect(docs == [.init(title: "A", source: "s", body: "x"), .init(title: "B", source: "set.json", body: "y")])
        // Not a list of { title, body }: the whole text is one document.
        let notDocs = try DocumentImport.parse(.init(name: "x.JSON", sizeBytes: 10, text: #"{"a":1}"#))
        #expect(notDocs == [.init(title: "x", source: "x.JSON", body: #"{"a":1}"#)])
        #expect(try DocumentImport.parse(.init(name: "t.csv", sizeBytes: 10, text: "a,b\r\n\r\n c,d\n")).first?.body == "a | b\n c | d")
        #expect(throws: DocumentImport.TooLarge.self) { try DocumentImport.parse(.init(name: "big.txt", sizeBytes: 25_000_001, text: "")) }
        #expect(throws: Never.self) { try DocumentImport.parse(.init(name: "big.pdf", sizeBytes: 99_000_000, text: "")) }
    }

    @Test func chunkTextOverlapsAndTrims() {
        #expect(DocumentImport.chunkText("   ").isEmpty)
        #expect(DocumentImport.chunkText("  short  ") == ["short"])
        let long = String(repeating: "a", count: 5000)
        let pieces = DocumentImport.chunkText(long)
        #expect(pieces.map(\.count) == [2000, 2000, 1400])
        #expect(DocumentImport.slug("  Hello, World!! ") == "hello-world")
    }

    @Test func aStoppedImportRemovesTheHalfMadeCollection() async throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        let calls = Embedded()
        await #expect(throws: SeedCorpus.Stopped.self) {
            _ = try await DocumentImport.importDocuments(
                kb: kb, embed: { calls.add($0); return [1] }, files: [.init(name: "a.txt", sizeBytes: 1, text: String(repeating: "word ", count: 2000))],
                collectionName: "A", collectionId: "c", shouldStop: { calls.values.count >= 2 }
            )
        }
        #expect(try kb.collections().isEmpty)
        #expect(try kb.chunkCount() == 0)
    }
}

/// Collects the texts an embed closure saw.
final class Embedded: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
