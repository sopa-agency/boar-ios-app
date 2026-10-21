import Foundation
import Testing
@testable import BoarCore

/// The SQL features the knowledge base relies on: FTS5 with bm25, fts5vocab, blobs, transactions. (zstd's counterpart lives in BoarRAGTests.)
@Suite struct SqlTests {
    @Test func fts5RanksWithBm25AndFts5vocabListsTerms() throws {
        let db = try SqliteDatabase.inMemory()
        defer { db.close() }
        try db.exec("CREATE VIRTUAL TABLE t USING fts5(title, body, tokenize='porter unicode61')")
        try db.transaction {
            try db.execute("INSERT INTO t(title, body) VALUES (?, ?)", args: ["Season", "Seasons come from the tilt of Earth's axis."])
            try db.execute("INSERT INTO t(title, body) VALUES (?, ?)", args: ["Monsoon", "A monsoon is a seasonal wind."])
        }
        let hits = try db.query("SELECT title FROM t WHERE t MATCH ? ORDER BY bm25(t, 2.0, 1.0)", args: ["season OR tilt"]) { $0.string(0) }
        #expect(hits.first == "Season")
        try db.exec("CREATE VIRTUAL TABLE v USING fts5vocab(t, 'row')")
        let terms = try db.query("SELECT term FROM v WHERE term = ?", args: ["season"]) { try $0.string("term") }
        #expect(terms == ["season"])
    }

    @Test func blobsAndNullsRoundTrip() throws {
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE b(id INTEGER PRIMARY KEY, v BLOB, n TEXT)")
        let vec = Data([1, 0xFE, 127, 0x80])
        try db.execute("INSERT INTO b(v, n) VALUES (?, ?)", args: [.blob(vec), nil])
        let row = try db.query("SELECT v, n FROM b") { (blob: $0.blob(0), isNull: $0.isNull(1)) }.first
        #expect(row?.blob == vec)
        #expect(row?.isNull == true)
    }

    // MARK: beyond the Kotlin test

    @Test func theSystemSqliteHasFts5() throws {
        let db = try SqliteDatabase.inMemory()
        let opts = try db.query("PRAGMA compile_options") { $0.string(0) ?? "" }
        #expect(opts.contains("ENABLE_FTS5"))
        #expect(SqliteDatabase.version.hasPrefix("3."))
    }

    @Test func argumentTypesBindAndReadBack() throws {
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE a(i INTEGER, r REAL, s TEXT, b BLOB, f INTEGER)")
        try db.execute("INSERT INTO a VALUES (?,?,?,?,?)", args: [SqlValue(Int64(1) << 40), 2.5, "naïve ☃ \u{0}x", .blob(Data()), true])
        let r = try db.query("SELECT * FROM a") { row in
            (try row.long("i"), try row.double("r"), try row.string("s"), try row.blob("b"), try row.long("f"), row.columnCount, row.columnName(1))
        }.first!
        #expect(r.0 == 1 << 40)
        #expect(r.1 == 2.5)
        #expect(r.2 == "naïve ☃ \u{0}x")
        #expect(r.3 == Data())
        #expect(r.4 == 1)
        #expect(r.5 == 5 && r.6 == "r")
        #expect(SqlValue(Optional<String>.none) == .null)
        #expect(SqlValue(Float(1.5)) == .real(1.5))
    }

    @Test func executeCountsChangesAndLastInsertRowid() throws {
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE c(id INTEGER PRIMARY KEY, v INT)")
        try db.execute("INSERT INTO c(v) VALUES (1), (2), (3)")
        #expect(db.lastInsertRowid() == 3)
        #expect(try db.execute("UPDATE c SET v = v + 1 WHERE v > ?", args: [1]) == 2)
    }

    @Test func aFailedTransactionRollsBackAndNestedOnesJoin() throws {
        struct Boom: Error {}
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE t(v INT)")
        #expect(throws: Boom.self) {
            try db.transaction {
                try db.execute("INSERT INTO t VALUES (1)")
                try db.transaction { try db.execute("INSERT INTO t VALUES (2)") }
                throw Boom()
            }
        }
        #expect(try db.query("SELECT count(*) FROM t") { $0.long(0) } == [0])
        try db.transaction { try db.transaction { try db.execute("INSERT INTO t VALUES (3)") } }
        #expect(try db.query("SELECT count(*) FROM t") { $0.long(0) } == [1])
    }

    @Test func errorsCarryTheCodeAndTheSql() throws {
        let db = try SqliteDatabase.inMemory()
        do { _ = try db.query("SELEKT 1") { $0.long(0) }; Issue.record("should throw") }
        catch let e as SqlError { #expect(e.code == 1); #expect(e.message.contains("SELEKT")) }
        let row = try db.query("SELECT 1 AS one") { row in (try? row.long("two")) }
        #expect(row == [nil])
    }

    @Test func aClosedDatabaseThrowsMisuseInsteadOfCrashing() throws {
        let db = try SqliteDatabase.inMemory()
        db.close()
        db.close()
        do { _ = try db.query("SELECT 1") { $0.long(0) }; Issue.record("should throw") }
        catch let e as SqlError { #expect(e.code == 21) }
    }

    @Test func fileDatabasesOpenReadOnlyAndRejectWrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-sql-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("p.sqlite").path
        let rw = try SqliteDatabase(path: path)
        try rw.exec("CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES ('format','2')")
        rw.close()
        let ro = try SqliteDatabase(path: path, readOnly: true)
        #expect(try ro.query("SELECT value FROM meta WHERE key = ?", args: ["format"]) { $0.string(0) } == ["2"])
        #expect(throws: SqlError.self) { try ro.execute("INSERT INTO meta VALUES ('a','b')") }
        #expect(throws: SqlError.self) { _ = try SqliteDatabase(path: dir.appendingPathComponent("missing/none.sqlite").path, readOnly: true) }
    }

    @Test func concurrentCallersShareOneConnectionSafely() async throws {
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE n(v INT)")
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { _ = try? db.transaction { try db.execute("INSERT INTO n VALUES (?)", args: [SqlValue(i)]) } }
            }
        }
        #expect(try db.query("SELECT count(*) FROM n") { $0.long(0) } == [50])
    }
}
