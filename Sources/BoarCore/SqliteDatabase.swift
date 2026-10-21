import Foundation
import SQLite3

// Thin, non-generic helpers over the C API so `SqlRow` (in Sql.swift) stays free of `import SQLite3`.
func sqlite3ColumnCount(_ st: OpaquePointer) -> Int32 { sqlite3_column_count(st) }
func sqlite3ColumnName(_ st: OpaquePointer, _ i: Int32) -> String { sqlite3_column_name(st, i).map { String(cString: $0) } ?? "" }
func sqlite3ColumnIsNull(_ st: OpaquePointer, _ i: Int32) -> Bool { sqlite3_column_type(st, i) == SQLITE_NULL }
func sqlite3ColumnInt64(_ st: OpaquePointer, _ i: Int32) -> Int64 { sqlite3_column_int64(st, i) }
func sqlite3ColumnDouble(_ st: OpaquePointer, _ i: Int32) -> Double { sqlite3_column_double(st, i) }
func sqlite3ColumnText(_ st: OpaquePointer, _ i: Int32) -> String? {
    if sqlite3_column_type(st, i) == SQLITE_NULL { return nil }
    guard let p = sqlite3_column_text(st, i) else { return "" }
    let n = Int(sqlite3_column_bytes(st, i))
    return String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self)
}
func sqlite3ColumnBlob(_ st: OpaquePointer, _ i: Int32) -> Data? {
    if sqlite3_column_type(st, i) == SQLITE_NULL { return nil }
    let n = Int(sqlite3_column_bytes(st, i))
    guard n > 0, let p = sqlite3_column_blob(st, i) else { return Data() }
    return Data(bytes: p, count: n)
}

/// The system SQLite (FTS5 included) behind `SqlDatabase`. One connection shared by every caller: a recursive lock holds it
/// for each call and for a whole transaction, so another thread's statements can't land inside someone else's BEGIN…COMMIT.
public final class SqliteDatabase: SqlDatabase, @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var txDepth = 0

    private static let misuse: Int = Int(SQLITE_MISUSE)
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens (creating, unless `readOnly`) the database at `path`.
    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        if rc != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open \(path)"
            if let handle { sqlite3_close_v2(handle) }
            throw SqlError(code: Int(rc), message: "\(msg) (\(path))")
        }
        db = handle
    }

    /// A private in-memory database.
    public static func inMemory() throws -> SqliteDatabase { try SqliteDatabase(path: ":memory:") }

    /// The linked SQLite's version, e.g. "3.51.0".
    public static var version: String { String(cString: sqlite3_libversion()) }

    deinit { if let db { sqlite3_close_v2(db) } }

    public func query<T>(_ sql: String, args: [SqlValue], map: (SqlRow) throws -> T) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        let st = try prepare(sql, args)
        defer { sqlite3_finalize(st) }
        let row = SqlRow(statement: st)
        var out: [T] = []
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_ROW { out.append(try map(row)) }
            else if rc == SQLITE_DONE { return out }
            else { throw error(rc) }
        }
    }

    @discardableResult
    public func execute(_ sql: String, args: [SqlValue]) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let st = try prepare(sql, args)
        defer { sqlite3_finalize(st) }
        var rc: Int32
        repeat { rc = sqlite3_step(st) } while rc == SQLITE_ROW
        if rc != SQLITE_DONE { throw error(rc) }
        return sqlite3_changes64(db)
    }

    public func exec(_ script: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let db else { throw SqlError(code: Self.misuse, message: "database is closed") }
        let rc = sqlite3_exec(db, script, nil, nil, nil)
        if rc != SQLITE_OK { throw error(rc) }
    }

    public func lastInsertRowid() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    @discardableResult
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        if txDepth > 0 { return try block() }
        try exec("BEGIN")
        txDepth += 1
        defer { txDepth -= 1 }
        do {
            let r = try block()
            try exec("COMMIT")
            return r
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Aborts a statement running on another thread (it throws `SQLITE_INTERRUPT`).
    public func interrupt() {
        // Deliberately lock-free: sqlite3_interrupt is meant to be called while another thread holds the connection.
        if let db { sqlite3_interrupt(db) }
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        if let db { sqlite3_close_v2(db); self.db = nil }
    }

    private func prepare(_ sql: String, _ args: [SqlValue]) throws -> OpaquePointer {
        // A pack closed by reloadPacks while a search still holds it: an error the retriever skips, never a crash.
        guard let db else { throw SqlError(code: Self.misuse, message: "database is closed") }
        var st: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &st, nil)
        guard rc == SQLITE_OK, let st else {
            if let st { sqlite3_finalize(st) }
            throw SqlError(code: Int(rc), message: "\(message()) in: \(sql.prefix(200))")
        }
        for (k, v) in args.enumerated() {
            let i = Int32(k + 1)
            let brc: Int32
            switch v {
            case .null: brc = sqlite3_bind_null(st, i)
            case .integer(let x): brc = sqlite3_bind_int64(st, i, x)
            case .real(let x): brc = sqlite3_bind_double(st, i, x)
            case .text(let s):
                brc = s.withCString { sqlite3_bind_text64(st, i, $0, sqlite3_uint64(s.utf8.count), Self.transient, UInt8(SQLITE_UTF8)) }
            case .blob(let d):
                brc = d.isEmpty ? sqlite3_bind_zeroblob(st, i, 0)
                    : d.withUnsafeBytes { sqlite3_bind_blob64(st, i, $0.baseAddress, sqlite3_uint64(d.count), Self.transient) }
            }
            if brc != SQLITE_OK { sqlite3_finalize(st); throw error(brc) }
        }
        return st
    }

    private func message() -> String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed" }
    private func error(_ rc: Int32) -> SqlError { SqlError(code: Int(rc), message: message()) }
}
