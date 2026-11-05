import Foundation

/// An answer or a whole chat as Markdown (android engine/chat `ChatExport.kt`): the question, the reasoning when there is
/// one, the answer, its numbered sources and the details line. Boar Press's Markdown file is built from it.
public enum ChatExport {
    public struct Labels: Sendable, Equatable {
        public var reasoning: String
        public var sources: String
        public init(reasoning: String, sources: String) { self.reasoning = reasoning; self.sources = sources }
    }

    public struct Turn: Sendable, Equatable {
        public var question: String?
        public var answer: String
        public var reasoning: String?
        /// (title, source) pairs, numbered in order.
        public var sources: [(String, String?)]
        public var details: String?

        public init(question: String?, answer: String, reasoning: String?, sources: [(String, String?)], details: String?) {
            self.question = question; self.answer = answer; self.reasoning = reasoning; self.sources = sources; self.details = details
        }

        public static func == (a: Turn, b: Turn) -> Bool {
            a.question == b.question && a.answer == b.answer && a.reasoning == b.reasoning && a.details == b.details
                && a.sources.map(\.0) == b.sources.map(\.0) && a.sources.map(\.1) == b.sources.map(\.1)
        }
    }

    public static func turn(_ t: Turn, _ l: Labels) -> String {
        var out = ""
        if let q = t.question?.kotlinTrim(), !q.isEmpty {
            out += "## " + q.replacingOccurrences(of: "\n", with: " ") + "\n\n"
        }
        if let r = t.reasoning?.kotlinTrim(), !r.isEmpty {
            out += "> 💭 **" + l.reasoning + "**\n>\n"
            for line in r.kotlinLines() { out += (line.allSatisfy(\.isWhitespace) ? ">" : "> " + line) + "\n" }
            out += "\n"
        }
        out += t.answer.kotlinTrim() + "\n"
        if !t.sources.isEmpty {
            out += "\n**" + l.sources + "**\n\n"
            for (i, (title, source)) in t.sources.enumerated() {
                out += "\(i + 1). " + title
                if let source, !source.allSatisfy(\.isWhitespace), source != title { out += " — " + source }
                out += "\n"
            }
        }
        if let d = t.details, !d.allSatisfy(\.isWhitespace) { out += "\n_" + d + "_\n" }
        return out
    }

    public static func chat(_ title: String, _ turns: [Turn], _ l: Labels) -> String {
        "# " + title.kotlinTrim().replacingOccurrences(of: "\n", with: " ") + "\n\n" + turns.map { turn($0, l) }.joined(separator: "\n---\n\n")
    }

    /// "boar-2026-10-15-why-is-the-sky-blue.md": the date, then the title in plain lowercase letters and digits.
    public static func fileName(_ title: String, date: String) -> String {
        // NFD, then the combining marks dropped (Kotlin \p{M}+), then lowercase.
        let plain = String(String.UnicodeScalarView(title.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            !($0.properties.generalCategory == .nonspacingMark || $0.properties.generalCategory == .spacingMark
                || $0.properties.generalCategory == .enclosingMark)
        })).lowercased()
        var slug = ""
        var dash = false
        for u in plain.unicodeScalars {
            if ("a"..."z").contains(u) || ("0"..."9").contains(u) {
                if dash, !slug.isEmpty { slug += "-" }
                dash = false
                slug.unicodeScalars.append(u)
            } else {
                dash = true
            }
        }
        // Kotlin: trim('-') then take(48) then trimEnd('-').
        slug = String(slug.prefix(48))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "boar-\(date).md" : "boar-\(date)-\(slug).md"
    }
}

extension String {
    /// Kotlin's `trim()`: drops leading and trailing characters that are whitespace (`Char.isWhitespace`).
    func kotlinTrim() -> String {
        var s = Substring(self)
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }

    /// Kotlin's `lines()`: split on \r\n, \n or \r, keeping empty lines (and a last empty one after a final break).
    func kotlinLines() -> [String] {
        replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
