import Foundation

/// A JSON document node. The settings store, the engine-tweak persistence and the `EngineParams`/`Sampling` JSON all use it,
/// so unknown keys survive a read-modify-write (the Kotlin side's `JsonElement`).
public enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parses a JSON text; nil when it isn't valid JSON.
    public init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8), let v = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        self = v
    }

    /// Compact JSON text with sorted keys (stable output).
    public var jsonString: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    public var isNull: Bool { if case .null = self { return true } else { return false } }

    /// The member of an object; nil for other cases or a missing key.
    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }

    /// Only a JSON string (Kotlin: a `JsonPrimitive` with `isString`).
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }

    /// Kotlin `intOrNull` on a primitive: a number with an integral value, or a string that reads as one.
    public var intValue: Int? {
        switch self {
        case .int(let v): return Int(exactly: v)
        case .double(let d): return Int(exactly: d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    /// Kotlin `toLongOrNull` on the primitive's content.
    public var int64Value: Int64? {
        switch self {
        case .int(let v): return v
        case .double(let d): return Int64(exactly: d)
        case .string(let s): return Int64(s)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    /// Kotlin `booleanOrNull` on a primitive: a boolean, or the strings "true"/"false".
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "true" ? true : s == "false" ? false : nil
        default: return nil
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not JSON") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { $1 })) }
}

extension JSONValue {
    public init(_ v: Int) { self = .int(Int64(v)) }
    public init(_ v: Bool) { self = .bool(v) }
    public init(_ v: String) { self = .string(v) }
    public init(_ v: Double) { self = .double(v) }
    public init(_ v: Float) { self = .double(Double(v)) }
    public init(strings: [String]) { self = .array(strings.map { .string($0) }) }
}
