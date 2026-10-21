import BoarCore
import Foundation

/// The user's own documents as a searchable collection (port of src/services/documentImporter.ts): text, Markdown, CSV
/// and JSON (a list of { title, body } documents, or any JSON as text) cut into overlapping ~500-token chunks and embedded
/// into the knowledge base. Same ids, titles and chunks as the TS (golden test). PDF text is extracted by the caller.
public enum DocumentImport {
    private static let charsPerToken = 4
    public static let chunkChars = 500 * charsPerToken
    public static let overlapChars = 50 * charsPerToken

    /// importLimits.ts: the largest file of each kind, in bytes.
    public static let textLimit: Int64 = 25_000_000
    public static let pdfLimit: Int64 = 100_000_000

    public struct Doc: Sendable, Equatable {
        public var title: String
        public var source: String
        public var body: String
        public init(title: String, source: String, body: String) { self.title = title; self.source = source; self.body = body }
    }

    public struct File: Sendable, Equatable {
        public var name: String
        public var sizeBytes: Int64
        public var text: String
        public init(name: String, sizeBytes: Int64, text: String) { self.name = name; self.sizeBytes = sizeBytes; self.text = text }
    }

    public struct Planned: Sendable, Equatable {
        public var chunks: [Chunk]
        public var docCount: Int
    }

    public struct TooLarge: Error, Equatable, CustomStringConvertible, LocalizedError {
        public var message: String
        public var description: String { message }
        public var errorDescription: String? { message }
    }

    /// chunkText: overlapping slices of the trimmed text (one chunk when it's short; none when empty).
    public static func chunkText(_ text: String) -> [String] {
        let t = Js.trim(text)
        if t.isEmpty { return [] }
        let n = t.u16Count
        if n <= chunkChars { return [t] }
        var out: [String] = []
        var start = 0
        while start < n {
            let end = min(start + chunkChars, n)
            out.append(t.u16Sub(start, end))
            if end >= n { break }
            start = end - overlapChars
        }
        return out
    }

    private static let newline = Rx("\\r?\\n")

    /// csvToText: one line per row, cells joined with " | ".
    public static func csvToText(_ raw: String) -> String {
        newline.split(raw).filter { !Js.trim($0).isEmpty }
            .map { $0.components(separatedBy: ",").joined(separator: " | ") }
            .joined(separator: "\n")
    }

    private static let ext = Rx("\\.[^.]+$")
    private static let nonAlnum = Rx("[^a-z0-9]+")
    private static let edgeDash = Rx("^-|-$")

    /// exportCollection's file: JSON.stringify(docs, null, 2), keys in title, source, body order.
    public static func exportJson(_ docs: [CollectionDoc]) -> String {
        if docs.isEmpty { return "[]" }
        let items = docs.map { d in
            "  {\n    \"title\": \(jsQuote(d.title)),\n    \"source\": \(jsQuote(d.source)),\n    \"body\": \(jsQuote(d.body))\n  }"
        }
        return "[\n" + items.joined(separator: ",\n") + "\n]"
    }

    /// JSON.stringify of a string.
    static func jsQuote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    public static func slug(_ s: String) -> String {
        let a = edgeDash.replace(nonAlnum.replace(s.lowercased(), with: "-"), with: "")
        return a.u16Take(60)
    }

    /// parseFileContent for text-based files (`File.text` is the PDF's extracted text for a .pdf).
    public static func parse(_ file: File) throws -> [Doc] {
        let lower = file.name.lowercased()
        let ext = lower.lastIndex(of: ".").map { String(lower[lower.index(after: $0)...]) } ?? lower
        let limit = ext == "pdf" ? pdfLimit : textLimit
        if file.sizeBytes > limit {
            throw TooLarge(message: "\"\(file.name)\" is too large (max \(limit / 1_000_000) MB). Split it into smaller files.")
        }
        let title = Self.ext.replace(file.name, with: "")
        if ext == "json" {
            if let parsed = JSONValue(jsonString: file.text), case .array(let items) = parsed,
               items.allSatisfy({ $0.objectValue?["title"]?.stringValue != nil && $0.objectValue?["body"]?.stringValue != nil }) {
                return items.map { d in
                    let o = d.objectValue!
                    return Doc(title: o["title"]!.stringValue!, source: o["source"]?.stringValue ?? file.name, body: o["body"]!.stringValue!)
                }
            }
            return [Doc(title: title, source: file.name, body: file.text)]
        }
        if ext == "csv" { return [Doc(title: title, source: file.name, body: csvToText(file.text))] }
        return [Doc(title: title, source: file.name, body: file.text)]
    }

    /// The collection's chunks: ids "<collection>-doc<i>-<slug>-c<j>", titles "<title> (part j/n)" when a doc splits.
    public static func plan(collectionId: String, docs: [Doc]) -> Planned {
        var chunks: [Chunk] = []
        for (di, doc) in docs.enumerated() {
            let docId = "\(collectionId)-doc\(di)-\(slug(doc.title))"
            let pieces = chunkText(doc.body)
            for (i, body) in pieces.enumerated() {
                chunks.append(Chunk(
                    chunkId: "\(docId)-c\(i)", docId: docId, title: pieces.count > 1 ? "\(doc.title) (part \(i + 1)/\(pieces.count))" : doc.title,
                    body: body, source: doc.source, collectionId: collectionId
                ))
            }
        }
        return Planned(chunks: chunks, docCount: docs.count)
    }

    public static func collectionId(_ name: String, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        "custom-\(nowMs)-\(slug(name))"
    }

    /// importDocuments: parse, chunk, create the collection, embed each chunk as "title\nbody". On failure or stop the
    /// half-made collection is removed.
    public static func importDocuments(
        kb: KnowledgeBase, embed: @Sendable (String) async throws -> [Float], files: [File], collectionName: String,
        collectionId: String? = nil, onProgress: (_ done: Int, _ total: Int) -> Void = { _, _ in }, shouldStop: () -> Bool = { false }
    ) async throws -> String {
        let id = collectionId ?? Self.collectionId(collectionName)
        var docs: [Doc] = []
        for f in files { docs += try parse(f) }
        let planned = plan(collectionId: id, docs: docs)
        try kb.createCollection(
            id: id, name: collectionName, sourceFilename: files.map(\.name).joined(separator: ", "),
            docCount: Int64(docs.count), chunkCount: Int64(planned.chunks.count), sizeBytes: files.reduce(0) { $0 + $1.sizeBytes }
        )
        do {
            for (i, c) in planned.chunks.enumerated() {
                if shouldStop() { throw SeedCorpus.Stopped() }
                onProgress(i, planned.chunks.count)
                try kb.insertChunk(c, embedding: try await embed("\(c.title)\n\(c.body)"))
            }
            onProgress(planned.chunks.count, planned.chunks.count)
        } catch {
            try? kb.deleteCollection(id)
            throw error
        }
        return id
    }
}
