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

    /// getCollectionDocs: each distinct passage of a collection, in chunk order.
    public func collectionDocs(_ id: String) throws -> [CollectionDoc] {
        try db.query("SELECT DISTINCT title, body, source FROM chunks WHERE collection_id = ? ORDER BY chunk_id", args: [.text(id)]) { r in
            CollectionDoc(title: try r.string("title")!, source: try r.string("source") ?? "", body: try r.string("body")!)
        }
    }

    public func setCollectionActive(_ id: String, _ active: Bool) throws {
        try db.execute("UPDATE custom_collections SET active = ? WHERE id = ?", args: [.integer(active ? 1 : 0), .text(id)])
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
    /// its scale depends on the corpus). Hits carry their real similarity when they have an embedding.
    public func lexicalSearch(_ query: String, queryVec: [Float], limit: Int) throws -> [Chunk] {
        guard let lq = RagPure.buildLexicalQuery(query) else { return [] }
        let rows = try db.query(
            """
            SELECT f.chunk_id, f.doc_id, f.title, f.body, bm25(chunks_fts) AS rank, e.embedding
            FROM chunks_fts f
            JOIN chunks c ON c.chunk_id = f.chunk_id
            LEFT JOIN chunk_embeddings e ON e.chunk_id = f.chunk_id
            LEFT JOIN custom_collections cc ON cc.id = c.collection_id
            WHERE chunks_fts MATCH ? AND (c.collection_id IS NULL OR cc.active = 1)
            ORDER BY rank LIMIT ?
            """,
            args: [.text(lq.match), .integer(Int64(limit * Self.lexicalCandidateMultiplier))]
        ) { r in
            Chunk(
                chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "",
                score: -r.double(4), matchType: .lexical,
                similarity: r.blob(5).map { RagPure.cosine(queryVec, Self.fromBlob($0)) }
            )
        }
        return Array(RagPure.filterByTermCoverage(rows, lq.terms).prefix(max(0, limit)))
    }

    /// Brute-force cosine search over the stored embeddings, with the MIN_SEMANTIC_SIMILARITY floor.
    public func semanticSearch(_ queryVec: [Float], limit: Int) throws -> [Chunk] {
        let scored = try db.query(
            """
            SELECT c.chunk_id, c.doc_id, c.title, c.body, e.embedding
            FROM chunk_embeddings e
            JOIN chunks c ON c.chunk_id = e.chunk_id
            LEFT JOIN custom_collections cc ON cc.id = c.collection_id
            WHERE c.collection_id IS NULL OR cc.active = 1
            """,
            args: []
        ) { r in
            let sim = RagPure.cosine(queryVec, Self.fromBlob(r.blob(4)!))
            return Chunk(chunkId: r.string(0)!, docId: r.string(1)!, title: r.string(2) ?? "", body: r.string(3) ?? "", score: sim, matchType: .semantic, similarity: sim)
        }
        return Array(scored.stableSorted { $0.score > $1.score }.filter { $0.score >= RagPure.minSemanticSimilarity }.prefix(max(0, limit)))
    }

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
