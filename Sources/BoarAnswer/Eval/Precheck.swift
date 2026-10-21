import Foundation

/// The grading block of a boar-eval bench item (`questions.schema.json` `grading`).
public struct BenchGrading: Codable, Sendable, Equatable {
    public struct MustK: Codable, Sendable, Equatable {
        public var k: Int
        public var terms: [String]
        public init(k: Int, terms: [String]) { self.k = k; self.terms = terms }
    }

    /// "precheck", "venue-list", "firstaid" or "judge-only".
    public var type: String
    public var mustAny: [[String]]
    public var mustK: MustK?
    public var forbid: [[String]]
    public var refuseOk: Bool

    public init(type: String, mustAny: [[String]] = [], mustK: MustK? = nil, forbid: [[String]] = [], refuseOk: Bool = false) {
        self.type = type; self.mustAny = mustAny; self.mustK = mustK; self.forbid = forbid; self.refuseOk = refuseOk
    }

    private enum CodingKeys: String, CodingKey {
        case type, mustAny = "must_any", mustK = "must_k", forbid, refuseOk = "refuse_ok"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        mustAny = try c.decodeIfPresent([[String]].self, forKey: .mustAny) ?? []
        mustK = try c.decodeIfPresent(MustK.self, forKey: .mustK)
        forbid = try c.decodeIfPresent([[String]].self, forKey: .forbid) ?? []
        refuseOk = try c.decodeIfPresent(Bool.self, forKey: .refuseOk) ?? false
    }

    /// The phone grades only precheck items; the others need the computer (OSM venues, first-aid rules, the judge).
    public var checkedOnDevice: Bool { type == "precheck" }
}

/// precheck v2.2: the deterministic keyword check of an answer against a bench item's grading, a faithful port of
/// boar-eval `scorers/vendor/lantern/precheck.py` (`grade`, `refused`, `norm`; Fixtures/bench/precheck-golden.jsonl).
/// It agrees with blind hand labels 88 % of the time: an upper bound, not the bounty ratio.
public enum Precheck {
    public enum Status: String, Sendable, Equatable, CaseIterable {
        case pass
        case refused
        case confidentWrong = "confident-wrong"
        case failMissing = "fail-missing"
        case empty
        case missing
    }

    public struct Result: Sendable, Equatable {
        public var status: Status
        /// The matched forbid terms, the missing groups, or "ok"/"not-ok" for a refusal (precheck's second value).
        public var why: String
        public init(status: Status, why: String) { self.status = status; self.why = why }

        /// A refusal counts as a pass only where the item allows declining (score.py: refused is 0 points otherwise).
        public var passed: Bool { status == .pass || (status == .refused && why == "ok") }
    }

    /// Exact strings from boar-app src/routing/answer.ts, EN and PT.
    static let appRefusals = [
        "i didn't find this in this phone's library",
        "the passages found don't support this answer",
        "não encontrei isso no acervo deste celular",
        "os trechos encontrados não sustentam esta resposta",
    ]
    private static let genericRefusal = regex(
        "(don't|do not|cannot|can't|couldn't|could not) (have|find|cover|answer)"
            + "|not (in|covered by) (my|the) (offline )?(sources|packs|library)"
            + "|no (offline )?sources? (cover|mention|say)"
            + "|não (encontrei|tenho|consigo)", [.caseInsensitive])
    private static let detok: [(NSRegularExpression, String)] = [
        (regex("(\\d)\\. (\\d)"), "$1.$2"),
        (regex("(\\d), (\\d{3})\\b"), "$1,$2"),
    ]

    private static func regex(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Bench terms are data: a pattern ICU rejects never matches (precheck.py would raise; the golden file proves none do).
        (try? NSRegularExpression(pattern: p, options: o)) ?? (try! NSRegularExpression(pattern: "(?!)"))
    }

    private static func range(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    /// Curly apostrophes to straight, lower case, llama detokenizer spacing undone ("8. 3" → "8.3", "4, 000" → "4,000").
    public static func norm(_ s: String?) -> String {
        var out = (s ?? "").replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'").lowercased()
        for (rx, template) in detok {
            out = rx.stringByReplacingMatches(in: out, options: [], range: range(out), withTemplate: template)
        }
        return out
    }

    private static func isAlnum(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }

    /// A plain term needs a word boundary before it, and after it only when it is ≤ 4 characters or ends in a digit
    /// (so stems and plurals still match); "re:<regex>" is a regex (case-insensitive, multi-line).
    static func compile(_ term: String) -> NSRegularExpression {
        if term.hasPrefix("re:") { return regex(String(term.dropFirst(3)), [.caseInsensitive, .anchorsMatchLines]) }
        let t = norm(term)
        let pre = isAlnum(t.first) ? "\\b" : ""
        let post = isAlnum(t.last) && (t.unicodeScalars.count <= 4 || (t.last?.isNumber ?? false)) ? "\\b" : ""
        return regex(pre + NSRegularExpression.escapedPattern(for: t) + post, [.caseInsensitive])
    }

    static func hits(_ term: String, _ text: String) -> Bool {
        compile(term).firstMatch(in: text, options: [], range: range(text)) != nil
    }

    /// Repeating the question is not evidence: plain must terms found in the question are ignored.
    static func isEcho(_ term: String, _ question: String) -> Bool { !term.hasPrefix("re:") && hits(term, question) }

    /// Declined, or an app / generic refusal in the first 200 characters of the normalized answer.
    static func refused(declined: Bool, _ text: String) -> Bool {
        if declined { return true }
        let head = String(String.UnicodeScalarView(text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(200)))
        return appRefusals.contains { head.contains($0) } || genericRefusal.firstMatch(in: head, options: [], range: range(head)) != nil
    }

    /// grade(q, row): nil `answer` means no row for the item.
    public static func grade(question: String, grading g: BenchGrading, answer: String?, declined: Bool = false) -> Result {
        guard let answer else { return Result(status: .missing, why: "") }
        let text = norm(answer)
        let q = norm(question)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Result(status: .empty, why: "") }
        let bad = g.forbid.flatMap { $0 }.filter { hits($0, text) }
        if !bad.isEmpty { return Result(status: .confidentWrong, why: bad.joined(separator: "; ")) }
        if refused(declined: declined, text) { return Result(status: .refused, why: g.refuseOk ? "ok" : "not-ok") }
        var missing: [String] = []
        for group in g.mustAny {
            let live = group.filter { !isEcho($0, q) }
            if !live.contains(where: { hits($0, text) }) {
                missing.append(live.first ?? "(echo-only group \(pythonRepr(group)))")
            }
        }
        if let mk = g.mustK {
            let live = mk.terms.filter { !isEcho($0, q) }
            let got = live.filter { hits($0, text) }
            if got.count < mk.k {
                missing.append("must_k \(got.count)/\(mk.k) (\(got.isEmpty ? "none" : got.joined(separator: ", ")))")
            }
        }
        if !missing.isEmpty { return Result(status: .failMissing, why: missing.joined(separator: "; ")) }
        return Result(status: .pass, why: "")
    }

    /// Python's repr of a list of strings, as precheck.py formats an echo-only group.
    static func pythonRepr(_ items: [String]) -> String {
        "[" + items.map { s in
            let quote: Character = s.contains("'") && !s.contains("\"") ? "\"" : "'"
            var out = String(quote)
            for c in s {
                switch c {
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case quote: out += "\\\(c)"
                default: out.append(c)
                }
            }
            return out + String(quote)
        }.joined(separator: ", ") + "]"
    }
}
