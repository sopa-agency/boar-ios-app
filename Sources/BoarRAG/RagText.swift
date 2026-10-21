import Foundation

/// "Why"/"what causes" questions: the passage with the question's other words first (port of src/rag/explain.ts).
public enum Explain {
    static let explainIntent = Rx(
        "(?i)\(Js.b0)(why|what (?:causes?|makes|drives|triggers|produces)|how (?:does|do|did|is|are|can)|reason|por ?que|o que (?:causa|faz|provoca|gera)|como (?:funciona|acontece|se forma|ocorre))\(Js.b1)"
    )

    /// EXPLAIN_INTENT.containsMatchIn(query).
    public static func hasExplainIntent(_ query: String) -> Bool { explainIntent.contains(query) }

    public static func termsBeyondTitle(_ terms: [LexicalTerm], _ title: String) -> [LexicalTerm] {
        terms.filter { RagPure.countMatchedTerms(title, [$0]) == 0 }
    }

    /// Reorders each title's chunks among the slots it already holds; a moved chunk takes its slot's score.
    public static func explainingFirst(_ items: [Chunk], _ terms: [LexicalTerm]) -> [Chunk] {
        var out = items
        var byTitle: [String: [Int]] = [:]
        for (i, c) in items.enumerated() { byTitle[c.title, default: []].append(i) }
        for (title, slots) in byTitle {
            if slots.count < 2 { continue }
            let beyond = termsBeyondTitle(terms, title)
            if beyond.isEmpty { continue }
            let ranked = slots.enumerated()
                .map { (order, i) in (chunk: items[i], order: order, share: RagPure.countMatchedTerms(items[i].body, beyond)) }
                .stableSorted { a, b in a.share != b.share ? a.share > b.share : a.order < b.order }
            for (k, slot) in slots.enumerated() {
                var moved = ranked[k].chunk
                moved.score = items[slot].score
                out[slot] = moved
            }
        }
        return out
    }
}

/// One copy of an article's passage per answer (port of src/rag/dedupe.ts).
public enum Dedupe {
    public static let copyMinShare = 0.6
    private static let word = Rx("[\\p{L}\\p{N}]+")

    private static func words(_ t: String) -> [String] { word.all(t.lowercased()).map(\.value) }
    private static func pairs(_ t: String) -> [String] {
        let w = words(t)
        return w.count < 2 ? [] : (1..<w.count).map { "\(w[$0 - 1]) \(w[$0])" }
    }

    public static func containedShare(_ a: String, _ b: String) -> Double {
        let inA = Set(pairs(a))
        let pb = pairs(b)
        if pb.isEmpty {
            let wa = Set(words(a))
            return words(b).allSatisfy { wa.contains($0) } ? 1.0 : 0.0
        }
        return Double(pb.filter { inA.contains($0) }.count) / Double(pb.count)
    }

    public static func dedupeArticleCopies(_ chunks: [Chunk]) -> [Chunk] {
        var kept: [Chunk] = []
        for c in chunks {
            let title = kotlinTrim(c.title).lowercased()
            let copy = kept.contains { k in
                kotlinTrim(k.title).lowercased() == title
                    && (containedShare(k.body, c.body) >= copyMinShare || containedShare(c.body, k.body) >= copyMinShare)
            }
            if !copy { kept.append(c) }
        }
        return kept
    }
}

/// Standards named by number: EIP-1559, ERC-20, BIP-32 (port of src/rag/identifiers.ts).
public enum Identifiers {
    private static let id = Rx("(?i)\(Js.b0)(EIP|ERC|BIP)(?:-|\(Js.ws))?(\\d{1,5})\(Js.b1)")

    public static func identifiersIn(_ query: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for m in id.all(query) {
            let s = "\(m.group(1)!.uppercased())-\(Int(m.group(2)!)!)"
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    public static func titleHasIdentifier(_ title: String, _ id: String) -> Bool {
        let parts = id.components(separatedBy: "-")
        let kind = parts[0], n = parts[1]
        return Rx("(?i)\(Js.b0)\(kind)(?:-|\(Js.ws))?0*\(n)\(Js.b1)").contains(title)
    }
}

/// Portuguese questions against English sources (port of src/rag/ptLexicon.ts).
public enum PtLexicon {
    /// The Portuguese-name → English-article-name lexicon (assets/lexicon/pt-en.json). Entries keep the file's order, which
    /// decides ties when two articles share a normalized name.
    public final class Lexicon: @unchecked Sendable {
        public let keys: [String]
        public let values: [String]
        private let index: [String: Int]
        private let lock = NSLock()
        private var titleIndex: [String: String]?

        /// `entries` in file order; a repeated key keeps its first position and takes the last value.
        public init(entries: [(key: String, value: String)]) {
            var keys: [String] = [], values: [String] = [], index: [String: Int] = [:]
            for (k, v) in entries {
                if let at = index[k] { values[at] = v } else { index[k] = keys.count; keys.append(k); values.append(v) }
            }
            self.keys = keys; self.values = values; self.index = index
        }

        /// From a dictionary (iteration order unspecified: prefer `init(jsonData:)` for the real lexicon).
        public convenience init(_ dictionary: [String: String]) {
            self.init(entries: dictionary.map { (key: $0.key, value: $0.value) })
        }

        /// From the JSON object text `{ "name": "English name", … }`, keeping the key order.
        public convenience init(jsonData: Data) throws {
            self.init(entries: try FlatJSONObject.parse(jsonData))
        }

        public var count: Int { keys.count }
        public subscript(key: String) -> String? { index[key].map { values[$0] } }

        /// `lexicon.values.associateBy { normalizeKey(it) }`: the last value wins; built once.
        func englishTitle(_ normalized: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            if titleIndex == nil {
                var m: [String: String] = [:]
                m.reserveCapacity(values.count)
                for v in values { m[PtLexicon.normalizeKey(v)] = v }
                titleIndex = m
            }
            return titleIndex![normalized]
        }
    }

    private static let qualifier = Rx("\(Js.ws)*\\([^)]*\\)\(Js.ws)*$")
    private static let spaces = Rx("\(Js.ws)+")

    public static func normalizeKey(_ s: String) -> String {
        var t = s.utf8.allSatisfy({ $0 < 0x80 }) ? s.lowercased() : Js.fold(s)
        if t.utf16.contains(0x28) { t = qualifier.replace(t, with: "") }
        return Js.trim(spaces.replace(t, with: " "))
    }

    private static let ptMarkers: Set<String> = [
        "o", "os", "que", "como", "porque", "qual", "quais", "uma", "um", "sao", "nao", "e", "das", "dos", "nas", "nos", "numa", "num",
        "pelo", "pela", "onde", "quando", "quanto", "quantos", "existem", "fazer", "faco", "devo", "entre", "diferenca", "depois", "antes",
        "em", "para", "com", "se", "posso", "pode", "tem", "funciona",
    ] // "por que" can't match a single word, as in the TS regex
    private static let asciiWord = Rx("[a-z0-9]+")
    private static let accented = Rx("(^|[^\\p{L}])[a-z\u{00E0}-\u{00FF}]*[\u{00E3}\u{00F5}\u{00E7}\u{00E2}\u{00EA}\u{00F4}\u{00E1}\u{00E9}\u{00ED}\u{00F3}\u{00FA}]\\p{L}*")

    public static func looksPortuguese(_ query: String) -> Bool {
        let words = asciiWord.all(Js.fold(query)).map(\.value)
        let hits = words.filter { ptMarkers.contains($0) }.count
        let hasAccent = accented.contains(query)
        return hits >= 2 || (hits >= 1 && (hasAccent || words.count <= 4))
    }

    private static let stop: Set<String> = Set((
        "a o as os um uma uns umas de do da dos das em no na nos nas num numa por para com sem que como qual quais quando onde porque se ao aos "
            + "e ou \u{00E9} nao mais menos muito entre sobre ate apos depois antes existem existe fazer faco devo pode posso quanto quantos quanta quantas isso isto esse essa este esta the of and"
    ).components(separatedBy: " "))

    private static let singularRules: [(Rx, String)] = [
        (Rx("oes$"), "ao"), (Rx("aes$"), "ao"), (Rx("ais$"), "al"), (Rx("eis$"), "el"), (Rx("ois$"), "ol"),
        (Rx("is$"), "il"), (Rx("ns$"), "m"), (Rx("res$"), "r"), (Rx("zes$"), "z"), (Rx("s$"), ""),
    ]

    public static func singularsPt(_ word: String) -> [String] {
        singularRules.filter { $0.0.contains(word) && word.u16Count > 3 }.map { $0.0.replaceFirst(word, with: $0.1) }
    }

    private static func variants(_ words: [String]) -> [String] {
        var out = [words.joined(separator: " ")]
        for i in words.indices {
            for s in singularsPt(words[i]) { out.append((Array(words[0..<i]) + [s] + Array(words[(i + 1)...])).joined(separator: " ")) }
        }
        return out
    }

    private static let foldedWord = Rx("[a-z0-9]+(?:-[a-z0-9]+)*")
    private static let originalWord = Rx("[\\p{L}\\p{N}]+(?:-[\\p{L}\\p{N}]+)*")
    private static let upperStart = Rx("^\\p{Lu}")

    /// English article names a Portuguese question mentions, longest names first, each word used once.
    public static func englishNamesIn(_ query: String, _ lexicon: Lexicon, max: Int = 4, maxLen: Int = 5) -> [String] {
        let words = foldedWord.all(Js.fold(query)).map(\.value)
        let original = originalWord.all(query).map(\.value)
        let accentedWords: [String]? = original.count == words.count ? original.map { Js.nfc($0).lowercased() } : nil
        let contentWords = words.filter { !stop.contains($0) && !ptMarkers.contains($0) }.count
        func capitalizedMid(_ i: Int) -> Bool { original.count == words.count && i > 0 && upperStart.contains(original[i]) }
        func specific(_ i: Int) -> Bool { words[i].u16Count >= 7 || contentWords <= 2 || capitalizedMid(i) }
        var used = [Bool](repeating: false, count: words.count)
        var names: [String] = []
        for len in stride(from: Swift.min(maxLen, words.count), through: 1, by: -1) {
            for i in 0...(words.count - len) {
                if names.count >= max { return names }
                let gram = Array(words[i..<(i + len)])
                if (i..<(i + len)).contains(where: { used[$0] }) { continue }
                if stop.contains(gram[0]) || stop.contains(gram[len - 1]) { continue }
                if len == 1 && (gram[0].u16Count < 4 || !specific(i)) { continue }
                var hit: String? = accentedWords.flatMap { lexicon[$0[i..<(i + len)].joined(separator: " ")] }
                if hit == nil {
                    for v in variants(gram) {
                        if let x = lexicon[v], !x.isEmpty { hit = x; break }
                    }
                }
                if hit == nil && len == 1 { hit = lexicon.englishTitle(gram[0]) }
                guard let h = hit else { continue }
                if h.isEmpty { continue } // as in the TS: an empty lexicon value ends the search for this gram
                if len == 1 && h.contains("(") && !capitalizedMid(i) { continue }
                for j in i..<(i + len) { used[j] = true }
                if !names.contains(h) { names.append(h) }
            }
        }
        return names
    }
}

/// A flat JSON object of string values read in file order (the lexicon is 6.5 MB; a dictionary would lose its order).
enum FlatJSONObject {
    struct ParseError: Error, CustomStringConvertible { var description: String }

    static func parse(_ data: Data) throws -> [(key: String, value: String)] {
        let b = [UInt8](data)
        var p = 0
        func skipWs() { while p < b.count, b[p] == 0x20 || b[p] == 0x0A || b[p] == 0x0D || b[p] == 0x09 { p += 1 } }
        func fail(_ m: String) -> ParseError { ParseError(description: "\(m) at byte \(p)") }
        func string() throws -> String {
            guard p < b.count, b[p] == 0x22 else { throw fail("expected a string") }
            p += 1
            var start = p
            var out = ""
            var pendingHigh: UInt16?
            func flush(_ end: Int) { if end > start { out += String(decoding: b[start..<end], as: UTF8.self) } }
            while p < b.count {
                let c = b[p]
                if c == 0x22 { flush(p); p += 1; return out }
                if c == 0x5C {
                    flush(p)
                    p += 1
                    guard p < b.count else { break }
                    let e = b[p]
                    p += 1
                    switch e {
                    case 0x22: out += "\""
                    case 0x5C: out += "\\"
                    case 0x2F: out += "/"
                    case 0x62: out += "\u{08}"
                    case 0x66: out += "\u{0C}"
                    case 0x6E: out += "\n"
                    case 0x72: out += "\r"
                    case 0x74: out += "\t"
                    case 0x75:
                        guard p + 4 <= b.count, let v = UInt16(String(decoding: b[p..<(p + 4)], as: UTF8.self), radix: 16) else { throw fail("bad \\u escape") }
                        p += 4
                        if let hi = pendingHigh {
                            pendingHigh = nil
                            if (0xDC00...0xDFFF).contains(v) {
                                out += String(decoding: [hi, v], as: UTF16.self)
                                start = p
                                continue
                            }
                            out += "\u{FFFD}"
                        }
                        if (0xD800...0xDBFF).contains(v) { pendingHigh = v }
                        else if (0xDC00...0xDFFF).contains(v) { out += "\u{FFFD}" }
                        else { out += String(decoding: [v], as: UTF16.self) }
                    default: throw fail("bad escape")
                    }
                    start = p
                    continue
                }
                if pendingHigh != nil { out += "\u{FFFD}"; pendingHigh = nil }
                p += 1
            }
            throw fail("unterminated string")
        }
        var entries: [(key: String, value: String)] = []
        skipWs()
        guard p < b.count, b[p] == 0x7B else { throw fail("expected {") }
        p += 1
        skipWs()
        if p < b.count, b[p] == 0x7D { return entries }
        while true {
            skipWs()
            let k = try string()
            skipWs()
            guard p < b.count, b[p] == 0x3A else { throw fail("expected :") }
            p += 1
            skipWs()
            let v = try string()
            entries.append((k, v))
            skipWs()
            guard p < b.count else { throw fail("unexpected end") }
            if b[p] == 0x2C { p += 1; continue }
            if b[p] == 0x7D { return entries }
            throw fail("expected , or }")
        }
    }
}
