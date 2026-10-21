import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// Fixture lookup relative to this file (repo root → Fixtures/golden), no SwiftPM resources.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var golden: URL { root.appendingPathComponent("Fixtures/golden") }

    static func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    static func golden(_ name: String) throws -> JSONValue {
        let t = try text(golden.appendingPathComponent(name))
        guard let v = JSONValue(jsonString: t) else { throw FixtureError("not valid JSON: \(name)") }
        return v
    }

    /// The app's bundled assets (seed corpus) are not golden fixtures: Fixtures/assets/<path> when present, else the sibling
    /// boar-app checkout (the same files the Kotlin tests read via ../../assets).
    static func asset(_ path: String) throws -> URL {
        let candidates = [root.appendingPathComponent("Fixtures/assets/\(path)"), root.deletingLastPathComponent().appendingPathComponent("boar-app/assets/\(path)")]
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return url }
        throw FixtureError("asset \(path) not found; copy boar-app/assets/\(path) to Fixtures/assets/\(path)")
    }
}

struct FixtureError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

// MARK: JSON access with Kotlin's jsonPrimitive semantics

extension JSONValue {
    /// `JsonElement.str`: nil for JSON null, else the primitive's content.
    var str: String? {
        switch self {
        case .null: return nil
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
    var arr: [JSONValue] { arrayValue ?? [] }
    var obj: [String: JSONValue] { objectValue ?? [:] }
    var dbl: Double { doubleValue ?? .nan }
    var int: Int { intValue ?? 0 }
    var i64: Int64 { int64Value ?? 0 }
    var flag: Bool { boolValue ?? false }
    var strs: [String] { arr.compactMap(\.str) }
    var isNullValue: Bool { if case .null = self { return true } else { return false } }
    /// A member that may be absent or JSON null.
    func opt(_ key: String) -> JSONValue? {
        guard let v = self[key], !v.isNullValue else { return nil }
        return v
    }
}

func req(_ v: JSONValue?, _ what: String = "") throws -> JSONValue {
    guard let v else { throw FixtureError("missing JSON member \(what)") }
    return v
}

/// A chunk as the golden JSON spells it (chunkId, docId, title, body, score, …).
func goldenChunk(_ o: JSONValue) -> Chunk {
    Chunk(
        chunkId: o["chunkId"]?.str ?? "", docId: o["docId"]?.str ?? "", title: o["title"]?.str ?? "", body: o["body"]?.str ?? "",
        source: o["source"]?.str, score: o["score"]?.doubleValue ?? 0
    )
}

/// ConversationHistory from the golden `{turns: [{role, text}]}` shape; nil for null/absent.
func goldenHistory(_ e: JSONValue?) -> ConversationHistory? {
    guard let e, !e.isNullValue else { return nil }
    return ConversationHistory(turns: e["turns"]?.arr.map { ConversationTurn(role: $0["role"]?.str ?? "", text: $0["text"]?.str ?? "") } ?? [])
}

/// A counter shared with a `@Sendable` closure that a recorded generator or retriever advances.
final class Cursor: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    /// The current value; `next()` returns it and advances.
    func next() -> Int { lock.withLock { defer { n += 1 }; return n } }
    var value: Int { lock.withLock { n } }
}

/// Strings gathered from a `@Sendable` closure.
final class Log<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []
    func add(_ e: Element) { lock.withLock { items.append(e) } }
    var all: [Element] { lock.withLock { items } }
}
