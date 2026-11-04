import BoarCore
import BoarRAG
import Foundation
import Testing

/// Document import must make the same collection and chunks as importDocuments (scripts/export-native-golden-import.mjs),
/// except for Markdown, which the native app cuts at its headings (Oct 21): there each heading starts one part, and the
/// other files of the same import still match the TS. The native app adds a card for each long file (Oct 23,
/// OwnFiles.card), after the parts: the TS comparison is on the parts.
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
            #expect(m.sizeBytes == col["sizeBytes"]!.i64)
            // A Markdown file's parts follow its headings, not the TS's fixed slices.
            func isMarkdown(_ source: String?) -> Bool { (source ?? "").hasSuffix(".md") }
            let headings = files.filter { isMarkdown($0.name) }.reduce(0) { n, f in
                n + f.text.components(separatedBy: "\n").filter { $0.hasPrefix("# ") || $0.hasPrefix("## ") }.count
            }
            let markdown = headings > 0
            let all = try db.query("SELECT chunk_id, doc_id, title, body, source, collection_id FROM chunks ORDER BY rowid") { r in (0...5).map { r.string($0) } }
            let cards = all.filter { $0[0]!.hasSuffix(OwnFiles.cardSuffix) }
            let rows = all.filter { !$0[0]!.hasSuffix(OwnFiles.cardSuffix) }
            // Cards come last, one per long file that is one document.
            #expect(try DocumentImport.cards(collectionId: id, files: files).map(\.chunkId) == cards.map { $0[0]! }, "\(name)")
            #expect(Array(all.prefix(rows.count)) == rows, "\(name)")
            let want: [[String?]] = run["chunks"]!.arr.map { c in ["chunkId", "docId", "title", "body", "source"].map { c[$0]!.str } + [id] }
            #expect(rows.filter { !isMarkdown($0[4]) } == want.filter { !isMarkdown($0[4]) }, "\(name)")
            #expect(rows.filter { isMarkdown($0[4]) }.count == headings, "\(name)")
            #expect(m.chunkCount == Int64(all.count))
            if !markdown { #expect(col["chunkCount"]!.i64 == Int64(rows.count)) }
            let parts = Array(embedded.values.prefix(rows.count))
            if !markdown {
                #expect(parts == run["embedded"]!.arr.map { $0.str! }, "\(name)")
            } else {
                #expect(parts == rows.map { "\($0[2]!)\n\($0[3]!)" }, "\(name)")
            }
            #expect(Array(embedded.values.dropFirst(rows.count)) == cards.map { "\($0[2]!)\n\($0[3]!)" }, "\(name)")
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

/// Files over 25 MB are turned away before they're read (DocumentImportLimitTest.kt); unknown sizes are read, capped.
@Suite struct DocumentImportLimitTests {
    @Test func theReadLimitIs25MB() {
        #expect(!DocumentImport.tooLargeToRead(25_000_000))
        #expect(DocumentImport.tooLargeToRead(25_000_001))
        #expect(DocumentImport.tooLargeToRead(90_000_000))
        #expect(!DocumentImport.tooLargeToRead(0))
        #expect(!DocumentImport.tooLargeToRead(-1))
    }

    @Test func onlyTheKindsBOARReadsAreImported() {
        for name in ["a.txt", "notes.MD", "x.markdown", "t.csv", "d.json", "paper.pdf"] { #expect(DocumentImport.readable(name), "\(name)") }
        for name in ["page.html", "letter.docx", "noext", "archive.zip"] { #expect(!DocumentImport.readable(name), "\(name)") }
    }
}
