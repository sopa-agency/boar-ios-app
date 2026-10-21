import BoarCore
import Foundation

/// Indexes the bundled corpus and downloaded corpus packs into the knowledge base (port of src/rag/seedCorpus.ts):
/// one chunk per document, id "wiki-<collection>-<slug of the title>" (the first document with a slug wins), embedded
/// as "title\nbody". Chunk ids match the Expo app's, so an upgraded install finds its index complete and skips it.
public final class SeedCorpus: Sendable {
    public struct Doc: Sendable, Equatable {
        public var id: String
        public var title: String
        public var source: String
        public var body: String
        public init(id: String, title: String, source: String, body: String) { self.id = id; self.title = title; self.source = source; self.body = body }
    }

    public struct Collection: Sendable {
        public var id: String
        public var docs: [Doc]
        public var error: String?
        public init(id: String, docs: [Doc], error: String? = nil) { self.id = id; self.docs = docs; self.error = error }
    }

    public struct Progress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        public var title: String
        public var collectionId: String
        public var collectionDone: Int
        public var collectionTotal: Int
    }

    public struct Stopped: Error, CustomStringConvertible, LocalizedError {
        public init() {}
        public var description: String { "seeding stopped" }
        public var errorDescription: String? { "seeding stopped" }
    }

    public struct BadCorpus: Error, CustomStringConvertible {
        public var description: String
    }

    private let kb: KnowledgeBase
    private let embed: @Sendable (String) async throws -> [Float]

    public init(kb: KnowledgeBase, embed: @escaping @Sendable (String) async throws -> [Float]) {
        self.kb = kb
        self.embed = embed
    }

    /// Indexes what's missing; returns how many documents it embedded.
    public func seed(
        _ collections: [Collection], onProgress: (Progress) -> Void = { _ in }, shouldStop: () -> Bool = { false }
    ) async throws -> Int {
        try kb.deleteSeedChunks(Self.retiredSeedIds)
        let total = collections.reduce(0) { $0 + $1.docs.count }
        let count = try kb.seedChunkCount()
        if count == Int64(total) { return 0 }
        var done = 0
        var embedded = 0
        var lastReport: Int64 = 0
        for c in collections {
            if c.error != nil { continue }
            for (i, doc) in c.docs.enumerated() {
                if shouldStop() { throw Stopped() }
                done += 1
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                if now - lastReport > 250 || done == total {
                    lastReport = now
                    onProgress(Progress(done: done, total: total, title: doc.title, collectionId: c.id, collectionDone: i + 1, collectionTotal: c.docs.count))
                }
                if try kb.hasChunk(doc.id) { continue }
                try kb.insertChunk(Chunk(chunkId: doc.id, docId: doc.id, title: doc.title, body: doc.body, source: doc.source), embedding: try await embed("\(doc.title)\n\(doc.body)"))
                embedded += 1
            }
        }
        return embedded
    }

    public static let builtin = "builtin"

    /// Seed chunks the app no longer ships (removed before seeding).
    public static let retiredSeedIds = ["app-moe-ram", "app-mmap-streaming", "app-bm25-vs-cosine", "app-grapheneos", "app-ram-budgeting"]

    private static let nonAlnum = Rx("[^a-z0-9]+")
    private static let edgeDash = Rx("^-|-$")

    public static func slug(_ title: String) -> String {
        edgeDash.replace(nonAlnum.replace(title.lowercased(), with: "-"), with: "")
    }

    public static func chunkIdPrefix(_ collectionId: String) -> String { "wiki-\(collectionId == builtin ? "min" : collectionId)-" }

    /// A corpus JSON file ([{ title, source, body }]) as seed documents, one per slug.
    public static func docs(collectionId: String, json: String) throws -> [Doc] {
        guard let parsed = JSONValue(jsonString: json), case .array(let items) = parsed else { throw BadCorpus(description: "not a JSON array") }
        var byId: [String: Doc] = [:]
        var order: [String] = []
        for e in items {
            guard let o = e.objectValue, let title = o["title"].flatMap(content), let body = o["body"].flatMap(content) else {
                throw BadCorpus(description: "a corpus entry needs a title and a body")
            }
            let id = chunkIdPrefix(collectionId) + slug(title)
            if byId[id] == nil {
                byId[id] = Doc(id: id, title: title, source: o["source"].flatMap(content) ?? "", body: body)
                order.append(id)
            }
        }
        return order.map { byId[$0]! }
    }

    /// Kotlin `jsonPrimitive.content`: the text of a string, number, boolean or null.
    private static func content(_ v: JSONValue) -> String? {
        switch v {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        default: return nil
        }
    }
}
