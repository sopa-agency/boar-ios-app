import Foundation

/// JSON as a plain tree with every number a Double (the Kotlin tests compare `tree(...)` values the same way).
indirect enum Tree: Equatable, Decodable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Tree])
    case object([String: Tree])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Tree].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Tree].self)) }
    }

    subscript(key: String) -> Tree {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool { if case .bool(let b) = self { return b }; return false }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var int: Int { Int(double ?? 0) }
    var int64: Int64? { double.map { Int64($0) } }
    var array: [Tree] { if case .array(let a) = self { return a }; return [] }
    var isNull: Bool { if case .null = self { return true }; return false }

    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return "\(b)"
        case .number(let n): return JsNumberPrint.string(n)
        case .string(let s): return "\"\(s)\""
        case .array(let a): return "[" + a.map(\.description).joined(separator: ", ") + "]"
        case .object(let o): return "{" + o.keys.sorted().map { "\($0): \(o[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}

enum JsNumberPrint {
    static func string(_ n: Double) -> String { n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : "\(n)" }
}

enum Golden {
    /// Repo root: this file is Tests/BoarRoutingTests/GoldenSupport.swift.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func load(_ name: String) throws -> Tree {
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/golden/\(name)"))
        return try JSONDecoder().decode(Tree.self, from: data)
    }
}

/// Collects mismatches the way the Kotlin tests do: all of them, each with its input.
struct Mismatches {
    private(set) var items: [String] = []
    mutating func add(input: String, want: Any, got: Any) {
        items.append("\(input)\n    want: \(want)\n    got:  \(got)")
    }
    var count: Int { items.count }
    func report(_ name: String, limit: Int = 15) -> String {
        "\(name): \(items.count) mismatches\n" + items.prefix(limit).joined(separator: "\n")
    }
}
