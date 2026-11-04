import BoarCore
@testable import BoarRAG
import Foundation
import Testing

/// A source under an answer, read whole (SourceArticleTest.kt), from each store it can come from, on a real SQLite.
@Suite struct SourceArticleTests {
    private let v: [Float] = [1, 0, 0]
    private let words = (1...900).map { "word\($0)" }.joined(separator: " ") // about 7,000 characters: four parts with overlap

    @Test func aPersonalFilesDocumentCutWithOverlapReadsBackAsTheFileOnce() throws {
        let parts = DocumentImport.chunkText(words)
        #expect(parts.count >= 3)
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        try kb.createCollection(id: "c", name: "notes", sourceFilename: "trip.txt", docCount: 1, chunkCount: Int64(parts.count), sizeBytes: Int64(words.utf16.count), now: 1)
        // Inserted out of order, and past c9: the parts sort by their number, not as text.
        for i in parts.indices.reversed() {
            try kb.insertChunk(Chunk(chunkId: "c-doc0-trip-c\(i)", docId: "c-doc0-trip", title: "trip (part \(i + 1)/\(parts.count))", body: parts[i], source: "trip.txt", collectionId: "c"), embedding: v)
        }
        let a = try #require(SourceArticle.read(docId: "c-doc0-trip", title: "trip (part 2/4)", kb: kb, packs: []))
        #expect(a.title == "trip")
        #expect(a.source == "trip.txt")
        #expect(a.text == words)
        #expect(!a.markdown)
    }

    @Test func aFilesCardIsNotReadAsPartOfTheFile() throws {
        let parts = DocumentImport.chunkText(words)
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        try kb.createCollection(id: "c", name: "notes", sourceFilename: "trip.txt", docCount: 1, chunkCount: Int64(parts.count), sizeBytes: Int64(words.utf16.count), now: 1)
        for (i, p) in parts.enumerated() {
            try kb.insertChunk(Chunk(chunkId: "c-doc0-trip-c\(i)", docId: "c-doc0-trip", title: "trip (part \(i + 1)/\(parts.count))", body: p, source: "trip.txt", collectionId: "c"), embedding: v)
        }
        // The card OwnFiles makes for a long file: same doc_id, its own chunk id.
        try kb.insertChunk(Chunk(chunkId: "c-doc0-trip\(OwnFiles.cardSuffix)", docId: "c-doc0-trip", title: "trip (about this file)", body: "File: trip.txt. Starts: word1 word2", source: "trip.txt", collectionId: "c"), embedding: v)
        #expect(SourceArticle.read(docId: "c-doc0-trip", title: "trip", kb: kb, packs: [])?.text == words)
    }

    @Test func partsPastC9KeepTheirOrder() throws {
        let joined = SourceArticle.join([String(repeating: "a", count: 30) + "XYZ", "XYZ" + String(repeating: "b", count: 30)])
        // 3 characters repeat: under the 20 a cut overlaps by.
        #expect(joined == String(repeating: "a", count: 30) + "XYZ\n\nXYZ" + String(repeating: "b", count: 30))
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        for i in [10, 2, 0, 1] { try kb.insertChunk(Chunk(chunkId: "d-c\(i)", docId: "d", title: "d", body: "part\(i).", source: "d.md"), embedding: v) }
        let a = try #require(SourceArticle.read(docId: "d", title: "d", kb: kb, packs: []))
        #expect(a.text == "part0.\n\npart1.\n\npart2.\n\npart10.")
        #expect(a.markdown)
    }

    @Test func aBuiltInLibraryDocumentReadsBack() throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        try kb.insertChunk(Chunk(chunkId: "wiki-min-boiling", docId: "wiki-min-boiling", title: "Boiling", body: "Boiling is the rapid vaporization of a liquid.", source: "https://en.wikipedia.org/wiki/Boiling"), embedding: v)
        let a = try #require(SourceArticle.read(docId: "wiki-min-boiling", title: "Boiling", kb: kb, packs: []))
        #expect(a.title == "Boiling")
        #expect(a.text == "Boiling is the rapid vaporization of a liquid.")
    }

    @Test func aSourceThatIsNoLongerOnThePhoneReadsAsNil() throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        #expect(SourceArticle.read(docId: "custom-gone-doc0-x", title: "x", kb: kb, packs: []) == nil)
        #expect(SourceArticle.read(docId: "pack:wiki-vital5:a12", title: "Nosebleed", kb: kb, packs: []) == nil) // the pack was removed
        #expect(SourceArticle.read(docId: "pack:old:Nosebleed", title: "Nosebleed", kb: kb, packs: []) == nil)
    }

    @Test func aFormat2PackArticleReadsWholeWithItsSourceLine() throws {
        let tmp = try Fixtures.tempDir("boar-read")
        let db = try SqliteDatabase(path: Fixtures.tempCopy(of: Fixtures.packs.appendingPathComponent("mini.sqlite"), in: tmp))
        let (id, title) = try #require(try db.query("SELECT id, title FROM articles ORDER BY id LIMIT 1", args: []) { r in (r.long(0), r.string(1)!) }.first)
        let pack = try WikiPack.open(db: db, zstd: ZstdDecoder())
        let a = try #require(SourceArticle.read(docId: "pack:local-mini:a\(id)", title: title, kb: KnowledgeBase(db: SqliteDatabase.inMemory()), packs: [.format2("local-mini", pack)]))
        #expect(a.title == title)
        #expect(a.text == (try pack.article(id)).text)
        #expect(a.source?.contains("https://") == true, "\(a.source ?? "nil")")
        #expect(a.markdown)
    }

    @Test func aFormat1PacksPassagesWithThatTitleReadBackInOrder() throws {
        let tmp = try Fixtures.tempDir("boar-read")
        let db = try SqliteDatabase(path: Fixtures.tempCopy(of: Fixtures.packs.appendingPathComponent("format1.sqlite"), in: tmp))
        let title = try #require(try db.query("SELECT title FROM chunks ORDER BY id LIMIT 1", args: []) { $0.string(0)! }.first)
        let bodies = try db.query("SELECT body FROM chunks WHERE title = ? ORDER BY id", args: [.text(title)]) { $0.string(0)! }
        let a = try #require(SourceArticle.read(docId: "pack:local-fixture:\(title)", title: title, kb: KnowledgeBase(db: SqliteDatabase.inMemory()), packs: [.format1("local-fixture", db)]))
        #expect(a.text == bodies.joined(separator: "\n\n"))
    }

    @Test func thePassageTheModelReadIsFoundAsIsWithoutItsSectionOrByItsStart() throws {
        let text = "Intro.\n\n## Treatment\nPinch the soft part of the nose for ten minutes. Lean forward, not back.\n\nMore text."
        let exact = "Pinch the soft part of the nose for ten minutes."
        let ns = text as NSString
        #expect(SourceArticle.passageAt(text, exact) == ns.range(of: exact))
        // Packs.packHitToChunk prefixes the section.
        let r = try #require(SourceArticle.passageAt(text, "Treatment: \(exact)"))
        #expect(ns.substring(with: r) == exact)
        // A passage the answer shortened (Compress drops sentences) still finds its unchanged start, 120 characters.
        let article = "Intro.\n\nPinch the soft part of the nose for ten minutes, leaning forward and breathing through the mouth, "
            + "then keep pinching for another five minutes if it still bleeds. Later sentence one. Later sentence two."
        let shortened = "Pinch the soft part of the nose for ten minutes, leaning forward and breathing through the mouth, "
            + "then keep pinching for another five minutes if it still bleeds. Later sentence two."
        #expect(SourceArticle.passageAt(article, shortened)?.location == (article as NSString).range(of: "Pinch").location)
        #expect(SourceArticle.passageAt(text, "Nothing like this is in the article.") == nil)
    }
}
