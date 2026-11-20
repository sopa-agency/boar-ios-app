import BoarCore
import Foundation

/// BOAR's knowledge about itself (android engine/rag `BoarPack.kt`, adam, 16 Nov; t9 0225, 0233): the BOAR Guide (one
/// passage per "## " section of each language's guide) and the BOAR FAQ written by Amandita, every language in one
/// built-in pack. Internal: not a knowledge pack the user sees, switches or deletes; never searched by Personal Files. Each
/// passage knows its language ("boar-<lang>-…"); its id carries a hash of its text, so an update replaces exactly what
/// changed. Adding a language later is adding its guide and FAQ text: nothing else changes.
public enum BoarPack {
    public struct Passage: Sendable, Equatable {
        public var id: String
        public var lang: String
        public var title: String
        public var source: String
        public var body: String
    }

    public struct BadFaq: Error, CustomStringConvertible {
        public var description: String
    }

    public static let prefix = "boar-"
    /// A section longer than this is split on its paragraphs: the search model reads 512 tokens.
    public static let maxChars = 1400

    private static let guideSource = ["en": "BOAR Guide", "pt": "Guia do BOAR"]

    // Java's `\s` is ASCII only (ICU's is Unicode): spelled out so the passages match Android's.
    private static let jws = "[ \\t\\n\\u000B\\f\\r]"
    private static let sections = Rx("(?m)^## ")
    private static let lineBreak = Rx("\\r\\n|\\n|\\r")
    private static let listMark = Rx("^\(jws)*[-*]\(jws)+")
    private static let link = Rx("\\[([^\\]]+)\\]\\([^)]+\\)")
    private static let blankRuns = Rx("\\n{3,}")
    private static let paragraphBreak = Rx("\\n\(jws)*\\n")

    /// The guide in `lang`: its "## " sections, each a passage titled "BOAR Guide · <section>".
    public static func guide(_ lang: String, markdown: String) -> [Passage] {
        let label = guideSource[lang] ?? "BOAR Guide"
        return sections.split(markdown).dropFirst().flatMap { sec -> [Passage] in
            // Kotlin substringBefore/After('\n') answer the whole string when there is no newline. By scalar, not Character:
            // a CRLF is one Character in Swift, so `firstIndex(of: "\n")` would miss it.
            let us = sec.unicodeScalars
            let nl = us.firstIndex(of: "\n")
            let heading = kotlinTrim(nl.map { String(us[..<$0]) } ?? sec)
            let body = plain(nl.map { String(us[us.index(after: $0)...]) } ?? sec)
            if heading.isEmpty || body.isEmpty { return [] }
            return parts(body).enumerated().map { i, b in
                passage(lang, "guide", heading + (i > 0 ? " (\(i + 1))" : ""), "\(label) · \(heading)", label, b)
            }
        }
    }

    /// The FAQ, every language it has: one passage per entry, the question as its title, the answer as its body.
    public static func faq(_ json: String) throws -> [Passage] {
        guard let root = JSONValue(jsonString: json)?.objectValue, let entries = root["entries"]?.arrayValue else { throw BadFaq(description: "no entries") }
        let sources = (root["source"]?.objectValue ?? [:]).compactMapValues { $0.stringValue }
        var out: [Passage] = []
        for e in entries {
            guard let o = e.objectValue else { throw BadFaq(description: "an entry is not an object") }
            // Each language is an object {q, a} under its code; "id" and "checked" are not languages. Kotlin keeps the file's
            // key order; a Swift dictionary has none, and the file lists en before pt, so the keys sort.
            for lang in o.keys.sorted() where lang.utf16.count == 2 && o[lang]?.objectValue != nil {
                guard let q = o[lang]?["q"]?.stringValue.map(kotlinTrim), let a = o[lang]?["a"]?.stringValue.map(kotlinTrim) else {
                    throw BadFaq(description: "\(lang) needs q and a")
                }
                let name = lang == "pt" ? "FAQ do BOAR" : "BOAR FAQ"
                out.append(passage(lang, "faq", q, "\(name) · \(q)", sources[lang] ?? name, "\(q)\n\(a)"))
            }
        }
        return out
    }

    public static func passages(guides: [String: String], faqJson: String?) throws -> [Passage] {
        // Kotlin maps keep insertion order; the languages sort here for a stable order.
        let g = guides.keys.sorted().flatMap { guide($0, markdown: guides[$0]!) }
        return g + (try faqJson.map(faq) ?? [])
    }

    private static func passage(_ lang: String, _ kind: String, _ key: String, _ title: String, _ source: String, _ body: String) -> Passage {
        let slug = String(SeedCorpus.slug(key).prefix(48))
        let hash = hex(javaHash(title + "\n" + body))
        return Passage(id: "\(prefix)\(lang)-\(kind)-\(slug)-\(hash)", lang: lang, title: title, source: source, body: body)
    }

    /// java.lang.String.hashCode: 31 * h + c over UTF-16 units, wrapping at 32 bits.
    static func javaHash(_ s: String) -> Int32 {
        var h: Int32 = 0
        for c in s.utf16 { h = h &* 31 &+ Int32(c) }
        return h
    }

    /// Integer.toHexString(h).padStart(8, '0'): the 32 bits, unsigned.
    private static func hex(_ h: Int32) -> String {
        let s = String(UInt32(bitPattern: h), radix: 16)
        return String(repeating: "0", count: max(0, 8 - s.count)) + s
    }

    /// Markdown to the plain text a passage holds: no list marks, no emphasis, no links' brackets.
    private static func plain(_ md: String) -> String {
        let lines = lineBreak.split(md).map { l -> String in
            var t = listMark.replace(l, with: "")
            t = t.replacingOccurrences(of: "**", with: "")
            t = link.replace(t) { $0.group(1) ?? "" }
            return kotlinTrimEnd(t)
        }
        return kotlinTrim(blankRuns.replace(lines.joined(separator: "\n"), with: "\n\n"))
    }

    private static func parts(_ body: String) -> [String] {
        if body.u16Count <= maxChars { return [body] }
        var out: [String] = []
        var cur = ""
        for p in paragraphBreak.split(body) {
            if !cur.isEmpty && cur.u16Count + p.u16Count > maxChars { out.append(kotlinTrim(cur)); cur = "" }
            cur += p + "\n\n"
        }
        if !kotlinTrim(cur).isEmpty { out.append(kotlinTrim(cur)) }
        return out
    }

    private static let boarSource = Rx("^(?:BOAR Guide|Guia do BOAR|BOAR FAQ|FAQ do BOAR)(?:$|,)")

    /// A source label BoarPack writes ("BOAR Guide", "FAQ do BOAR, escrito pela Amandita").
    public static func isBoarSource(_ source: String) -> Bool { boarSource.contains(kotlinTrim(source)) }

    /// The passage's language, from its id.
    public static func langOf(_ chunkId: String) -> String? {
        guard chunkId.hasPrefix(prefix) else { return nil }
        let rest = chunkId.dropFirst(prefix.count)
        return rest.firstIndex(of: "-").map { String(rest[..<$0]) } ?? String(rest)
    }

    /// A question about BOAR itself, EN or PT (t9 0225 item 3): BOAR named, the app itself, or a feature only BOAR has a
    /// name for. Generic words alone ("models", "offline", "battery") don't count: "models of the atom" isn't about BOAR.
    public static func aboutBoar(_ query: String) -> Bool {
        boar.contains(query) || app.contains(query) || feature.contains(query) || pin.contains(query)
    }

    private static let b = #"(?<![\p{L}\p{N}_])"#
    private static let e = #"(?![\p{L}\p{N}_])"#
    // Kotlin's IGNORE_CASE also sets UNICODE_CASE; ICU's case-insensitive match is Unicode.
    private static let boar = Rx(b + #"\$?boar"# + e, .caseInsensitive)
    private static let app = Rx(
        b + "(?:this app|the app|this application|o app|este app|esse app|o aplicativo|este aplicativo|esse aplicativo)" + e, .caseInsensitive
    )
    private static let feature = Rx(
        b + "(?:local files|arquivos locais|personal files|deep research|pesquisa profunda|knowledge packs?|pacotes? de conhecimento|boar labs|answer styles?|estilos? de resposta|model catalog|cat[áa]logo de modelos|boarverse|boar avatars?|starter profile|perfil iniciante|succinct & direct|thorough & detailed|sucinto e direto|completo e detalhado|my data|meus dados|telemetry|telemetria)"
            + e,
        .caseInsensitive
    )
    /// The app's PIN, written as such (not "pin a message").
    private static let pin = Rx(b + "(?:PIN|pin lock|pin code|bloqueio por pin|c[óo]digo pin)" + e)

    /// The floor for a BOAR passage: the semantic search's, not the answer gate's 0.7 (a PT question reads PT text lower).
    public static let minSimilarity = RagPure.minSemanticSimilarity

    /// BOAR's passages for a question in `lang` (t9 0233): the question's language first when it has a good one (at or
    /// above `minSimilarity`); otherwise the other language's, which the answer still uses in the question's language.
    public static func rank(_ hits: [Chunk], lang: String) -> [Chunk] {
        let good = hits.filter { ($0.similarity ?? 0.0) >= minSimilarity }.stableSorted { ($0.similarity ?? 0.0) > ($1.similarity ?? 0.0) }
        let own = good.filter { langOf($0.chunkId) == lang }
        let other = good.filter { langOf($0.chunkId) != lang }
        return own.isEmpty ? other : own + other
    }
}
