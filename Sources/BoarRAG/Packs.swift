import BoarCore
import Foundation

/// Knowledge packs as the chat's retrieval sees them (port of the pure parts of src/rag/packs.ts): format-1 search
/// (FTS5 candidates, then int8 cosine), the meta check, source URLs and format-2 hits as chunks.
public enum Packs {
    /// FTS5 candidates per format-1 pack that are compared with the question's embedding.
    public static let packCandidates = 400

    public static let sourceLabel: [PackSource: String] = [
        .enwiki: "Wikipedia",
        .enwikivoyage: "Wikivoyage",
        .enwikibooks: "Wikibooks",
        .appropedia: "Appropedia",
        .usgov: "US government",
        .eips: "Ethereum EIPs/ERCs",
        .ethspecs: "Ethereum specs",
        .ethereumorg: "ethereum.org",
        .bips: "Bitcoin BIPs",
    ]

    /// Format of a pack from its meta table, or nil when it isn't a pack for this app's embedding model.
    public static func packFormat(_ meta: [String: String], embeddingSha256: String) -> Int? {
        let v2 = meta["formatVersion"] == "2"
        let embeddingsOk = meta["embeddingModelSha256"] == embeddingSha256 || (v2 && (meta["embeddingModelSha256"] ?? "").isEmpty)
        if meta["format"] != "boar-knowledge-pack" || !embeddingsOk { return nil }
        return v2 ? 2 : 1
    }

    /// A recorded page URL made safe to show and open: spaces become underscores on wiki paths and %20 elsewhere,
    /// then any other unencoded character is encoded (JavaScript's encodeURI(decodeURI(url))).
    public static func normalizeUrl(_ url: String) -> String {
        let spaced = url.contains("/wiki/") ? url.replacingOccurrences(of: " ", with: "_") : url.replacingOccurrences(of: " ", with: "%20")
        guard let decoded = JsUri.decodeURI(spaced) else { return spaced }
        return JsUri.encodeURI(decoded)
    }

    public static func articleUrl(_ title: String, _ source: PackSource, url: String? = nil) -> String {
        if let url, !url.isEmpty { return normalizeUrl(url) }
        let host: String
        switch source {
        case .enwikivoyage: host = "en.wikivoyage.org"
        case .enwikibooks: host = "en.wikibooks.org"
        default: host = "en.wikipedia.org"
        }
        return "https://\(host)/wiki/\(JsUri.encodeURIComponent(title.replacingOccurrences(of: " ", with: "_")))"
    }

    /// A format-2 pack hit in the shape the chat's retrieval uses.
    public static func packHitToChunk(_ packId: String, _ h: PackHit) -> Chunk {
        let label = sourceLabel[h.source] ?? "Source"
        let license = (h.license ?? "").isEmpty ? "" : " (\(h.license!))"
        return Chunk(
            chunkId: "pack:\(packId):\(h.chunkId)",
            docId: "pack:\(packId):a\(h.articleId)",
            title: h.source == .enwiki ? h.title : "\(label): \(h.title)",
            body: h.section.isEmpty ? h.text : "\(h.section): \(h.text)",
            source: "\(label) \u{2014} \(articleUrl(h.title, h.source, url: h.url))\(license)",
            score: h.score,
            matchType: .lexical,
            action: h.action
        )
    }

    public struct Found: Sendable, Equatable {
        public var lexical: [Chunk]
        public var semantic: [Chunk]
    }

    /// Lexical and semantic candidates from one format-1 pack, scored like the built-in knowledge base's.
    public static func searchFormat1(
        _ db: any SqlDatabase, packId: String, query: String, queryVec: [Float], limit: Int, explain: Bool? = nil
    ) throws -> Found {
        guard let lq = RagPure.buildLexicalQuery(query) else { return Found(lexical: [], semantic: []) }
        struct Row { var id: Int64; var title: String; var body: String; var vec: Data; var rank: Double }
        let rows = try db.query(
            """
            SELECT c.id, c.title, c.body, c.vec, bm25(chunks_fts) AS rank
            FROM chunks_fts f JOIN chunks c ON c.id = f.rowid
            WHERE chunks_fts MATCH ? ORDER BY rank LIMIT ?
            """,
            args: [.text(lq.match), .integer(Int64(packCandidates))]
        ) { Row(id: $0.long(0), title: $0.string(1)!, body: $0.string(2)!, vec: $0.blob(3)!, rank: $0.double(4)) }
        func chunk(_ r: Row, _ score: Double, _ type: MatchType) -> Chunk {
            Chunk(
                chunkId: "pack:\(packId):\(r.id)", docId: "pack:\(packId):\(r.title)", title: r.title, body: r.body,
                score: score, matchType: type, similarity: RagPure.cosineInt8(queryVec, r.vec)
            )
        }
        var lex = Array(RagPure.filterByTermCoverage(rows.map { chunk($0, -$0.rank, .lexical) }, lq.terms).prefix(max(0, limit)))
        var sem = Array(
            rows.map { chunk($0, RagPure.cosineInt8(queryVec, $0.vec), .semantic) }
                .stableSorted { $0.score > $1.score }.filter { $0.score >= RagPure.minSemanticSimilarity }.prefix(max(0, limit))
        )
        if explain ?? Explain.hasExplainIntent(query) {
            lex = Explain.explainingFirst(lex, lq.terms)
            sem = Explain.explainingFirst(sem, lq.terms)
        }
        return Found(lexical: lex, semantic: sem)
    }
}

/// JavaScript's encodeURI, decodeURI and encodeURIComponent; malformed input makes `decodeURI` return nil (URIError).
public enum JsUri {
    private static let hex = Array("0123456789ABCDEF".utf8)
    private static let unescaped = Set("-_.!~*'()".unicodeScalars)
    private static let reserved = Set(";/?:@&=+$,".unicodeScalars)

    private static func alnum(_ c: Unicode.Scalar) -> Bool {
        (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9")
    }

    private static func encode(_ s: String, keep: (Unicode.Scalar) -> Bool) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if keep(u) { out.unicodeScalars.append(u); continue }
            for b in String(u).utf8 {
                out += "%"
                out.unicodeScalars.append(Unicode.Scalar(hex[Int(b >> 4)]))
                out.unicodeScalars.append(Unicode.Scalar(hex[Int(b & 15)]))
            }
        }
        return out
    }

    public static func encodeURIComponent(_ s: String) -> String { encode(s) { alnum($0) || unescaped.contains($0) } }
    public static func encodeURI(_ s: String) -> String { encode(s) { alnum($0) || unescaped.contains($0) || reserved.contains($0) || $0 == "#" } }

    /// Escapes of reserved characters and '#' stay as they are. Nil for a malformed escape.
    public static func decodeURI(_ s: String) -> String? {
        let u = Array(s.utf16)
        var out: [UInt16] = []
        var i = 0
        func isHex(_ c: UInt16) -> Bool { (0x30...0x39).contains(c) || (0x61...0x66).contains(c) || (0x41...0x46).contains(c) }
        func byteAt(_ k: Int) -> Int? {
            if k + 2 >= u.count || u[k] != 0x25 || !isHex(u[k + 1]) || !isHex(u[k + 2]) { return nil }
            return Int(String(decoding: u[(k + 1)...(k + 2)], as: UTF16.self), radix: 16)
        }
        while i < u.count {
            let c = u[i]
            if c != 0x25 { out.append(c); i += 1; continue }
            guard let b = byteAt(i) else { return nil }
            if b < 0x80 {
                let ch = Unicode.Scalar(UInt8(b))
                if reserved.contains(ch) || ch == "#" { out.append(contentsOf: u[i..<(i + 3)]) } else { out.append(UInt16(b)) }
                i += 3
                continue
            }
            let n: Int
            if b & 0xE0 == 0xC0 { n = 2 } else if b & 0xF0 == 0xE0 { n = 3 } else if b & 0xF8 == 0xF0 { n = 4 } else { return nil }
            if i + 3 * n > u.count { return nil }
            var bytes: [UInt8] = []
            for k in 0..<n {
                guard let x = byteAt(i + 3 * k) else { return nil }
                if k > 0 && x & 0xC0 != 0x80 { return nil }
                bytes.append(UInt8(x))
            }
            guard let text = String(validating: bytes, as: UTF8.self) else { return nil }
            out.append(contentsOf: Array(text.utf16))
            i += 3 * n
        }
        return String(decoding: out, as: UTF16.self)
    }
}
