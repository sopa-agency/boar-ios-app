import Foundation

/// A value bound to a `?` placeholder (by position): text, integer, real, blob or NULL.
/// Literals work in argument lists: `["Season", 1, 0.5, nil]`. Other values: `SqlValue(x)` for any `SqlBindable` (or its optional).
public enum SqlValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public init<T: SqlBindable>(_ v: T?) { self = v?.sqlValue ?? .null }
}

extension SqlValue: ExpressibleByNilLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByBooleanLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .real(value) }
    public init(stringLiteral value: String) { self = .text(value) }
    public init(booleanLiteral value: Bool) { self = .integer(value ? 1 : 0) }
}

/// Types that bind as a SQL value (Kotlin: String, Long/Int, Double/Float, ByteArray, Boolean).
public protocol SqlBindable: Sendable {
    var sqlValue: SqlValue { get }
}
extension String: SqlBindable { public var sqlValue: SqlValue { .text(self) } }
extension Int: SqlBindable { public var sqlValue: SqlValue { .integer(Int64(self)) } }
extension Int32: SqlBindable { public var sqlValue: SqlValue { .integer(Int64(self)) } }
extension Int64: SqlBindable { public var sqlValue: SqlValue { .integer(self) } }
extension Bool: SqlBindable { public var sqlValue: SqlValue { .integer(self ? 1 : 0) } }
extension Double: SqlBindable { public var sqlValue: SqlValue { .real(self) } }
extension Float: SqlBindable { public var sqlValue: SqlValue { .real(Double(self)) } }
extension Data: SqlBindable { public var sqlValue: SqlValue { .blob(self) } }
extension Array: SqlBindable where Element == UInt8 { public var sqlValue: SqlValue { .blob(Data(self)) } }

/// One result row, valid only inside the `map` closure of `query` (the statement steps on after it returns).
public struct SqlRow {
    let statement: OpaquePointer

    public var columnCount: Int { Int(sqlite3ColumnCount(statement)) }
    public func columnName(_ i: Int) -> String { sqlite3ColumnName(statement, Int32(i)) }
    public func isNull(_ i: Int) -> Bool { sqlite3ColumnIsNull(statement, Int32(i)) }
    public func long(_ i: Int) -> Int64 { sqlite3ColumnInt64(statement, Int32(i)) }
    public func int(_ i: Int) -> Int { Int(truncatingIfNeeded: long(i)) }
    public func double(_ i: Int) -> Double { sqlite3ColumnDouble(statement, Int32(i)) }
    /// nil for NULL.
    public func string(_ i: Int) -> String? { sqlite3ColumnText(statement, Int32(i)) }
    /// nil for NULL.
    public func blob(_ i: Int) -> Data? { sqlite3ColumnBlob(statement, Int32(i)) }

    /// The index of a column by name (first match); throws for an unknown name, as the Kotlin side does.
    public func index(_ name: String) throws -> Int {
        for i in 0..<columnCount where columnName(i) == name { return i }
        throw SqlError(code: 1, message: "no column \(name)")
    }
    public func long(_ name: String) throws -> Int64 { long(try index(name)) }
    public func int(_ name: String) throws -> Int { int(try index(name)) }
    public func double(_ name: String) throws -> Double { double(try index(name)) }
    public func string(_ name: String) throws -> String? { string(try index(name)) }
    public func blob(_ name: String) throws -> Data? { blob(try index(name)) }
}

public struct SqlError: Error, Equatable, CustomStringConvertible {
    public var code: Int
    public var message: String
    public init(code: Int, message: String) { self.code = code; self.message = message }
    public var description: String { "SQLite error \(code): \(message)" }
}

/// The SQL the engine needs, behind a protocol: the system SQLite with FTS5 (`SqliteDatabase`) on the device and in tests.
/// Arguments are bound by position (`?`). All methods are synchronous and serialized per connection.
public protocol SqlDatabase: Sendable {
    func query<T>(_ sql: String, args: [SqlValue], map: (SqlRow) throws -> T) throws -> [T]
    /// Runs one statement; returns the number of rows it changed.
    @discardableResult func execute(_ sql: String, args: [SqlValue]) throws -> Int64
    /// Runs a script of statements without arguments.
    func exec(_ script: String) throws
    func lastInsertRowid() -> Int64
    /// BEGIN … COMMIT around `block` (ROLLBACK when it throws). Nested calls join the outer transaction. No other thread's
    /// statement lands inside it.
    @discardableResult func transaction<T>(_ block: () throws -> T) throws -> T
    func close()
}

extension SqlDatabase {
    public func query<T>(_ sql: String, _ map: (SqlRow) throws -> T) throws -> [T] { try query(sql, args: [], map: map) }
    @discardableResult public func execute(_ sql: String) throws -> Int64 { try execute(sql, args: []) }
}

/// zstd frame decompression (format-2 pack blocks). The zstd-backed implementation lives in BoarRAG.
public protocol Zstd: Sendable {
    func decompress(_ src: Data) throws -> Data
}
