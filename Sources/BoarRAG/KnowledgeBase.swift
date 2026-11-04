import BoarCore
import Foundation

public struct CollectionDoc: Sendable, Equatable {
    public var title: String
    public var source: String
    public var body: String
    public init(title: String, source: String, body: String) { self.title = title; self.source = source; self.body = body }
}

/// The on-phone knowledge base (port of src/rag/db.ts + the searches of src/rag/retrieve.ts): an FTS5 table for
/// keyword search and float32 embeddings for semantic search, plus chat history, feedback, telemetry and user
/// collections. Same file and schema as the Expo app (files/SQLite/aoair_knowledge.db), so an upgrade keeps them.
public final class KnowledgeBase: Sendable {
    public struct Collection: Sendable, Equatable {
        public var id: String
        public var name: String
        public var sourceFilename: String?
        public var docCount: Int64
        public var chunkCount: Int64
        public var sizeBytes: Int64
        public var active: Bool
        public var createdAt: Int64
    }

    private let db: any SqlDatabase

    public init(db: any SqlDatabase) throws {
        self.db = db
        try migrate()
    }

    private func migrate() throws {
        try db.exec(Self.schema)
        let columns = try db.query("PRAGMA table_info(chunks)") { try $0.string("name") }
        if !columns.contains("collection_id") {
            try db.exec("ALTER TABLE chunks ADD COLUMN collection_id TEXT REFERENCES custom_collections(id)")
        }
        // A file's parts and a collection's chunks are looked up by these (the files' cards, a source read whole, a
        // collection removed): without an index each is a scan of every chunk. After the ALTER, which adds the column.
        try db.exec("CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(doc_id); CREATE INDEX IF NOT EXISTS idx_chunks_collection ON chunks(collection_id);")
    }

    public func insertChunk(_ chunk: Chunk, embedding: [Float]) throws {
        try db.transaction {
            try db.execute(
                "INSERT OR REPLACE INTO chunks (chunk_id, doc_id, title, body, source, collection_id) VALUES (?, ?, ?, ?, ?, ?)",
                args: [.text(chunk.chunkId), .text(chunk.docId), .text(chunk.title), .text(chunk.body), SqlValue(chunk.source), SqlValue(chunk.collectionId)]
            )
            try db.execute(
                "INSERT OR REPLACE INTO chunks_fts (chunk_id, doc_id, title, body) VALUES (?, ?, ?, ?)",
                args: [.text(chunk.chunkId), .text(chunk.docId), .text(chunk.title), .text(chunk.body)]
            )
            try db.execute(
                "INSERT OR REPLACE INTO chunk_embeddings (chunk_id, embedding, dim) VALUES (?, ?, ?)",
                args: [.text(chunk.chunkId), .blob(Self.toBlob(embedding)), .integer(Int64(embedding.count))]
            )
        }
    }

    /// Seed chunks (bundled corpus and corpus packs, not imported documents).
    public func seedChunkCount() throws -> Int64 {
        try db.query("SELECT COUNT(*) FROM chunks WHERE collection_id IS NULL") { $0.long(0) }.first ?? 0
    }

    public func hasChunk(_ chunkId: String) throws -> Bool {
        !(try db.query("SELECT 1 FROM chunks WHERE chunk_id = ?", args: [.text(chunkId)]) { _ in 1 }).isEmpty
    }

    public func chunkCount() throws -> Int64 {
        try db.query("SELECT COUNT(*) FROM chunks") { $0.long(0) }.first ?? 0
    }

    /// Deletes seed-corpus chunks (never user-imported ones) by id.
    public func deleteSeedChunks(_ ids: [String]) throws {
        if ids.isEmpty { return }
        let marks = ids.map { _ in "?" }.joined(separator: ", ")
        let seed = "SELECT chunk_id FROM chunks WHERE collection_id IS NULL AND chunk_id IN (\(marks))"
        let args = ids.map { SqlValue.text($0) }
        try db.transaction {
            try db.execute("DELETE FROM chunks_fts WHERE chunk_id IN (\(seed))", args: args)
            try db.execute("DELETE FROM chunk_embeddings WHERE chunk_id IN (\(seed))", args: args)
            try db.execute(seed.replacingOccurrences(of: "SELECT chunk_id FROM", with: "DELETE FROM"), args: args)
        }
    }

    private static let globSpecials = Rx("[*?\\[\\]]")

    /// Deletes seed-corpus chunks whose id starts with `prefix` (GLOB: case-sensitive, "_" literal); returns how many.
    @discardableResult
    public func deleteSeedChunksWithPrefix(_ prefix: String) throws -> Int64 {
        let pattern = Self.globSpecials.replace(prefix, with: "") + "*"
        let seed = "SELECT chunk_id FROM chunks WHERE collection_id IS NULL AND chunk_id GLOB ?"
        return try db.transaction {
            try db.execute("DELETE FROM chunks_fts WHERE chunk_id IN (\(seed))", args: [.text(pattern)])
            try db.execute("DELETE FROM chunk_embeddings WHERE chunk_id IN (\(seed))", args: [.text(pattern)])
            return try db.execute(seed.replacingOccurrences(of: "SELECT chunk_id FROM", with: "DELETE FROM"), args: [.text(pattern)])
        }
    }

    public func collections() throws -> [Collection] {
        try db.query("SELECT * FROM custom_collections ORDER BY created_at DESC") { r in
            Collection(
                id: try r.string("id")!, name: try r.string("name")!, sourceFilename: try r.string("source_filename"),
                docCount: try r.long("doc_count"), chunkCount: try r.long("chunk_count"), sizeBytes: try r.long("size_bytes"),
                active: try r.long("active") == 1, createdAt: try r.long("created_at")
            )
        }
    }

    public func createCollection(
        id: String, name: String, sourceFilename: String?, docCount: Int64, chunkCount: Int64, sizeBytes: Int64,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws {
        try db.execute(
            "INSERT INTO custom_collections (id, name, source_filename, doc_count, chunk_count, size_bytes, active, created_at) VALUES (?, ?, ?, ?, ?, ?, 1, ?)",
            args: [.text(id), .text(name), SqlValue(sourceFilename), .integer(docCount), .integer(chunkCount), .integer(sizeBytes), .integer(now)]
        )
    }

    /// getCollectionDocs: each distinct passage of a collection, in chunk order. Cards (OwnFiles.card) stay out: they're
    /// BOAR's index of a file, and a re-imported export would turn them into the user's text.
    public func collectionDocs(_ id: String) throws -> [CollectionDoc] {
        try db.query(
            "SELECT DISTINCT title, body, source FROM chunks WHERE collection_id = ? AND chunk_id NOT LIKE '%\(OwnFiles.cardSuffix)' ORDER BY chunk_id",
            args: [.text(id)]
        ) { r in
            CollectionDoc(title: try r.string("title")!, source: try r.string("source") ?? "", body: try r.string("body")!)
        }
    }

    /// One document's parts (the built-in library's, or a file in Personal Files), for reading it whole (SourceArticle).
    public func docParts(_ docId: String) throws -> [Chunk] {
        // Not the file's card (OwnFiles.card): it describes the file, it isn't part of its text.
        try db.query(
            "SELECT chunk_id, doc_id, title, body, source, collection_id FROM chunks WHERE doc_id = ? AND chunk_id NOT LIKE '%\(OwnFiles.cardSuffix)'",
            args: [.text(docId)]
        ) { r in
            Chunk(chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "", source: r.string(4), collectionId: r.string(5))
        }
    }

    public func setCollectionActive(_ id: String, _ active: Bool) throws {
        try db.execute("UPDATE custom_collections SET active = ? WHERE id = ?", args: [.integer(active ? 1 : 0), .text(id)])
    }

    public struct EraseError: Error, CustomStringConvertible {
        public var description: String { "the write-ahead log couldn't be emptied: a reader holds it" }
    }

    /// Every Personal Files collection erased so its text can't be read back from the database file (Forgot PIN): pages
    /// freed are overwritten (secure_delete), the search index is merged so the deleted words leave its segments, and the
    /// write-ahead log is emptied.
    public func eraseAllCollections() throws {
        try db.exec("PRAGMA secure_delete = ON")
        do {
            for c in try collections() { try deleteCollection(c.id) }
            try db.exec("INSERT INTO chunks_fts(chunks_fts) VALUES('optimize')")
        } catch {
            try? db.exec("PRAGMA secure_delete = OFF")
            throw error
        }
        try db.exec("PRAGMA secure_delete = OFF")
        // The log must really be emptied: a checkpoint blocked by a reader reports busy (its first column) instead of
        // failing. Retried for a moment; still busy, the erase fails, and Forgot PIN keeps the PIN.
        for _ in 0..<30 {
            let busy = try db.query("PRAGMA wal_checkpoint(TRUNCATE)") { $0.long(0) }.first ?? 0
            if busy == 0 { return }
            usleep(100_000)
        }
        throw EraseError()
    }

    public func deleteCollection(_ id: String) throws {
        let rows = "SELECT chunk_id FROM chunks WHERE collection_id = ?"
        try db.transaction {
            try db.execute("DELETE FROM chunk_embeddings WHERE chunk_id IN (\(rows))", args: [.text(id)])
            try db.execute("DELETE FROM chunks_fts WHERE chunk_id IN (\(rows))", args: [.text(id)])
            try db.execute("DELETE FROM chunks WHERE collection_id = ?", args: [.text(id)])
            try db.execute("DELETE FROM custom_collections WHERE id = ?", args: [.text(id)])
        }
    }

    /// BM25 keyword search over the question's content words, gated by term coverage (no numeric bm25 floor:
    /// its scale depends on the corpus). Hits carry their real similarity when they have an embedding. `ownOnly`: the
    /// user's collections only.
    public func lexicalSearch(_ query: String, queryVec: [Float], limit: Int, ownOnly: Bool = false) throws -> [Chunk] {
        guard let lq = RagPure.buildLexicalQuery(query) else { return [] }
        let rows = try db.query(
            """
            SELECT f.chunk_id, f.doc_id, f.title, f.body, bm25(chunks_fts) AS rank, e.embedding, c.collection_id
            FROM chunks_fts f
            JOIN chunks c ON c.chunk_id = f.chunk_id
            LEFT JOIN chunk_embeddings e ON e.chunk_id = f.chunk_id
            LEFT JOIN custom_collections cc ON cc.id = c.collection_id
            WHERE chunks_fts MATCH ? AND (c.collection_id IS NULL OR cc.active = 1)\(ownOnly ? Self.ownOnlyClause : "")
            ORDER BY rank LIMIT ?
            """,
            args: [.text(lq.match), .integer(Int64(limit * Self.lexicalCandidateMultiplier))]
        ) { r in
            Chunk(
                chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "",
                collectionId: r.string(6), score: -r.double(4), matchType: .lexical,
                similarity: r.blob(5).map { RagPure.cosine(queryVec, Self.fromBlob($0)) }
            )
        }
        return Array(RagPure.filterByTermCoverage(rows, lq.terms).prefix(max(0, limit)))
    }

    /// Brute-force cosine search over the stored embeddings, with a similarity floor (minSemanticSimilarity by default).
    /// `ownOnly`: the user's collections only.
    public func semanticSearch(
        _ queryVec: [Float], limit: Int, minSimilarity: Double = RagPure.minSemanticSimilarity, ownOnly: Bool = false
    ) throws -> [Chunk] {
        let scored = try db.query(
            """
            SELECT c.chunk_id, c.doc_id, c.title, c.body, e.embedding
            FROM chunk_embeddings e
            JOIN chunks c ON c.chunk_id = e.chunk_id
            LEFT JOIN custom_collections cc ON cc.id = c.collection_id
            WHERE (c.collection_id IS NULL OR cc.active = 1)\(ownOnly ? Self.ownOnlyClause : "")
            """,
            args: []
        ) { r in
            let sim = RagPure.cosine(queryVec, Self.fromBlob(r.blob(4)!))
            return Chunk(chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "", score: sim, matchType: .semantic, similarity: sim)
        }
        return Array(scored.stableSorted { $0.score > $1.score }.filter { $0.score >= minSimilarity }.prefix(max(0, limit)))
    }

    /// The documents of the switched-on collections, oldest collection first, with their file's name (the part's source)
    /// and their part count, cards left out (OwnFiles).
    public func ownFiles() throws -> [OwnFiles.File] {
        try db.query(
            """
            SELECT c.doc_id, MIN(c.source) AS name, SUM(CASE WHEN c.chunk_id LIKE '%\(OwnFiles.cardSuffix)' THEN 0 ELSE 1 END) AS parts
            FROM chunks c JOIN custom_collections cc ON cc.id = c.collection_id
            WHERE cc.active = 1
            GROUP BY c.doc_id ORDER BY MIN(cc.created_at), c.doc_id
            """,
            args: []
        ) { r in OwnFiles.File(docId: r.string(0)!, name: r.string(1) ?? r.string(0)!, parts: Int(r.long(2))) }
    }

    /// Each document's opening part ("<doc>-c0"), in `docIds`' order.
    public func openingParts(_ docIds: [String]) throws -> [Chunk] {
        if docIds.isEmpty { return [] }
        let ids = docIds.map { "\($0)-c0" }
        let rows = try db.query(
            "SELECT chunk_id, doc_id, title, body, source, collection_id FROM chunks WHERE chunk_id IN (\(ids.map { _ in "?" }.joined(separator: ", ")))",
            args: ids.map { .text($0) }
        ) { r in Chunk(chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "", source: r.string(4), collectionId: r.string(5)) }
        var byId: [String: Chunk] = [:]
        for c in rows { byId[c.chunkId] = c }
        return ids.compactMap { byId[$0] }
    }

    /// The parts of `docIds` (one file's documents), closest to `queryVec` first, with no similarity floor: the question
    /// named the file.
    public func rankWithin(_ docIds: [String], queryVec: [Float], limit: Int) throws -> [Chunk] {
        if docIds.isEmpty { return [] }
        let scored = try db.query(
            """
            SELECT c.chunk_id, c.doc_id, c.title, c.body, c.source, c.collection_id, e.embedding
            FROM chunks c JOIN chunk_embeddings e ON e.chunk_id = c.chunk_id
            WHERE c.doc_id IN (\(docIds.map { _ in "?" }.joined(separator: ", "))) AND c.chunk_id NOT LIKE '%\(OwnFiles.cardSuffix)'
            """,
            args: docIds.map { .text($0) }
        ) { r in
            let sim = RagPure.cosine(queryVec, Self.fromBlob(r.blob(6)!))
            return Chunk(
                chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "", source: r.string(4), collectionId: r.string(5),
                score: sim, matchType: .semantic, similarity: sim
            )
        }
        return Array(scored.stableSorted { $0.score > $1.score }.prefix(max(0, limit)))
    }

    /// Keeps a search to the user's own collections (the active ones, as the rest of the WHERE says).
    private static let ownOnlyClause = " AND c.collection_id IS NOT NULL"

    /// Extra BM25 candidates so the coverage gate has something to choose from.
    public static let lexicalCandidateMultiplier = 4
    public static let file = "SQLite/aoair_knowledge.db"

    /// float32, little-endian (what the Expo app stored).
    public static func toBlob(_ v: [Float]) -> Data {
        var d = Data(capacity: v.count * 4)
        for f in v {
            var bits = f.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { d.append(contentsOf: $0) }
        }
        return d
    }

    public static func fromBlob(_ b: Data) -> [Float] {
        let n = b.count / 4
        return b.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            (0..<n).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    private static let schema = """
        PRAGMA journal_mode = WAL;
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(chunk_id UNINDEXED, doc_id UNINDEXED, title, body);
        CREATE TABLE IF NOT EXISTS chunks (chunk_id TEXT PRIMARY KEY, doc_id TEXT NOT NULL, title TEXT, body TEXT NOT NULL, source TEXT);
        CREATE TABLE IF NOT EXISTS chunk_embeddings (chunk_id TEXT PRIMARY KEY REFERENCES chunks(chunk_id), embedding BLOB NOT NULL, dim INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS chat_sessions (id TEXT PRIMARY KEY, title TEXT NOT NULL, summary TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS chat_messages (id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES chat_sessions(id), role TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_chat_messages_session ON chat_messages(session_id, created_at);
        CREATE TABLE IF NOT EXISTS answer_feedback (message_id TEXT PRIMARY KEY REFERENCES chat_messages(id), rating TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS execution_telemetry (
          id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, model_id TEXT, task_type TEXT,
          adaptive_routing_used INTEGER NOT NULL DEFAULT 0, reason_codes TEXT, retrieval_used INTEGER, model_switches INTEGER,
          cross_message_model_switch INTEGER, model_residency TEXT, model_load_ms REAL, ttft_ms REAL, generation_latency_ms REAL,
          total_latency_ms REAL, tokens_generated INTEGER, tok_per_sec REAL, peak_rss_bytes INTEGER, outcome TEXT, error_message TEXT);
        CREATE INDEX IF NOT EXISTS idx_execution_telemetry_created ON execution_telemetry(created_at DESC);
        CREATE TABLE IF NOT EXISTS custom_collections (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, source_filename TEXT, doc_count INTEGER NOT NULL DEFAULT 0,
          chunk_count INTEGER NOT NULL DEFAULT 0, size_bytes INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL);
        """
}
