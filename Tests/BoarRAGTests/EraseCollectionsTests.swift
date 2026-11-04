import BoarCore
@testable import BoarRAG
import Foundation
import Testing

/// The erase behind the lock's "Erase Chats and Files" (EraseCollectionsTest.kt): a Personal Files text must not stay
/// readable in the database's files.
@Suite struct EraseCollectionsTests {
    private func onDisk(_ dir: URL) -> String {
        let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        return files.compactMap { try? Data(contentsOf: $0) }.map { String(decoding: $0.map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self) }.joined()
    }

    @Test func erasedFilesLeaveNoTextInTheDatabaseItsIndexOrItsLog() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "erase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try SqliteDatabase(path: dir.appending(path: "kb.db").path)
        try db.exec("PRAGMA journal_mode = WAL")
        let kb = try KnowledgeBase(db: db)
        try kb.insertChunk(Chunk(chunkId: "wiki-a", docId: "wiki-a", title: "Lisbon", body: "Lisbon is the capital of Portugal.", source: "wiki"), embedding: [1, 0, 0])
        try kb.createCollection(id: "c-diary", name: "diary", sourceFilename: "diary.txt", docCount: 1, chunkCount: 1, sizeBytes: 10, now: 1)
        for i in 0..<20 {
            try kb.insertChunk(Chunk(chunkId: "c-diary-doc0-c\(i)", docId: "c-diary-doc0", title: "diary", body: "zebracorn lighthouse appointment number \(i)",
                                     source: "diary.txt", collectionId: "c-diary"), embedding: [0, 1, 0])
        }
        #expect(onDisk(dir).contains("zebracorn"))
        try kb.eraseAllCollections()
        #expect(try kb.collections().isEmpty)
        #expect(!onDisk(dir).contains("zebracorn"), "the erased text is still in the database's files")
        // The built-in library is untouched.
        #expect(onDisk(dir).contains("Lisbon"))
    }

    @Test func anEraseThatCantEmptyTheLogFailsInsteadOfReportingSuccess() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "erase-busy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appending(path: "kb.db").path
        let db = try SqliteDatabase(path: path)
        try db.exec("PRAGMA journal_mode = WAL")
        let kb = try KnowledgeBase(db: db)
        try kb.createCollection(id: "c-diary", name: "diary", sourceFilename: "diary.txt", docCount: 1, chunkCount: 1, sizeBytes: 10, now: 1)
        try kb.insertChunk(Chunk(chunkId: "c-diary-doc0-c0", docId: "c-diary-doc0", title: "diary", body: "zebracorn", source: "diary.txt", collectionId: "c-diary"), embedding: [0, 1, 0])
        // Another connection in the middle of a read: the checkpoint can't truncate the log under it.
        let reader = try SqliteDatabase(path: path)
        try reader.exec("BEGIN")
        _ = try reader.query("SELECT count(*) FROM chunks") { $0.long(0) }
        #expect(throws: (any Error).self) { try kb.eraseAllCollections() }
        try reader.exec("ROLLBACK")
    }
}
