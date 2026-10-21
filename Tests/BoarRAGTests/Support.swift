import BoarCore
import BoarRAG
import Foundation
import Testing

/// Fixture lookup relative to this file (repo root → Fixtures/golden), no SwiftPM resources.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var golden: URL { root.appendingPathComponent("Fixtures/golden") }
    static var packs: URL { golden.appendingPathComponent("packs") }

    static func data(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    static func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    static func json(_ url: URL) throws -> JSONValue {
        let t = try text(url)
        guard let v = JSONValue(jsonString: t) else { throw FixtureError("not valid JSON: \(url.lastPathComponent)") }
        return v
    }

    static func golden(_ name: String) throws -> JSONValue { try json(golden.appendingPathComponent(name)) }

    /// The app's bundled assets (corpus, Portuguese lexicon) are not golden fixtures: Fixtures/assets/<path> when present,
    /// else the sibling boar-app checkout (the same files the Kotlin tests read via ../../assets).
    static func asset(_ path: String) throws -> URL {
        let candidates = [root.appendingPathComponent("Fixtures/assets/\(path)"), root.deletingLastPathComponent().appendingPathComponent("boar-app/assets/\(path)")]
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return url }
        throw FixtureError("asset \(path) not found; copy boar-app/assets/\(path) to Fixtures/assets/\(path)")
    }

    /// A private writable copy of a fixture file (WAL, temp tables: the fixture itself is never opened for writing).
    static func tempCopy(of url: URL, in dir: URL) throws -> String {
        let to = dir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: to)
        try FileManager.default.copyItem(at: url, to: to)
        return to.path
    }

    static func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-rag-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
    var strs: [String?] { arr.map(\.str) }
}

func req(_ v: JSONValue?, _ what: String = "") throws -> JSONValue {
    guard let v else { throw FixtureError("missing JSON member \(what)") }
    return v
}

/// A chunk as the golden JSON spells it (chunkId, docId, title, body, score, …).
func goldenChunk(_ o: JSONValue) -> Chunk {
    Chunk(
        chunkId: o["chunkId"]?.str ?? "", docId: o["docId"]?.str ?? "", title: o["title"]?.str ?? "", body: o["body"]?.str ?? "",
        source: o["source"]?.str, score: o["score"]?.doubleValue ?? 0,
        matchType: MatchType(rawValue: (o["matchType"]?.str ?? "lexical").lowercased()) ?? .lexical,
        similarity: o["similarity"]?.doubleValue, action: o["action"]?.boolValue ?? false
    )
}

/// Compares two retrieval results field by field. Scores that come out of SQLite's own `bm25()` agree only to the last
/// digit or two across SQLite builds and libm implementations (the goldens were made on another platform), so scores
/// are compared with a relative tolerance of 1e-12; everything else, and the order, must be identical.
func sameChunks(_ got: [Chunk], _ want: [Chunk]) -> Bool {
    guard got.count == want.count else { return false }
    for (g, w) in zip(got, want) {
        var a = ChunkLine(g), b = ChunkLine(w)
        if abs(a.score - b.score) > 1e-12 * max(1, abs(b.score)) { return false }
        a.score = 0; b.score = 0
        if a != b { return false }
    }
    return true
}

/// PacksGoldenTest.chunkLine: the fields a retrieval result is compared on.
struct ChunkLine: Equatable, CustomStringConvertible {
    var chunkId: String, docId: String, title: String, body: String, source: String?, score: Double, matchType: String, similarity: Double?, action: Bool
    init(_ c: Chunk) {
        chunkId = c.chunkId; docId = c.docId; title = c.title; body = c.body; source = c.source
        score = c.score; matchType = c.matchType.rawValue; similarity = c.similarity; action = c.action
    }
    var description: String {
        [chunkId, docId, title, body, source ?? "null", String(score), matchType, similarity.map { String($0) } ?? "null", String(action)].joined(separator: " | ")
    }
}

/// GoldenEmbedding.kt: content words hashed (FNV-1a over code points) into 384 floats, the golden exporter's stand-in embedding.
enum GoldenEmbedding {
    private static let stop: Set<String> = Set(
        ("what when where which who whom why how is are was were be the a an of in on at to and or for from with does do did can could "
            + "should would tell me about it its this that there qual quais o os a as que \u{00E9} um uma de do da dos das em no na por para com como")
            .components(separatedBy: " ")
    )
    private static let word = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")

    static func hashVec(_ text: String) -> [Float] {
        var v = [Float](repeating: 0, count: 384)
        let low = text.lowercased() as NSString
        for m in word.matches(in: low as String, range: NSRange(location: 0, length: low.length)) {
            let w = low.substring(with: m.range)
            if stop.contains(w) { continue }
            var h: UInt32 = 2166136261
            for cp in w.unicodeScalars { h = (h ^ cp.value) &* 16777619 }
            let u = UInt64(h)
            v[Int(u % 384)] += 1
            v[Int((u >> 9) % 384)] -= 0.5
        }
        return v
    }
}
