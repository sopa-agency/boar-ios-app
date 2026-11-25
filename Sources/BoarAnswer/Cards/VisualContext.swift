import Foundation

/// What the visual's model reads besides the answer (android `VisualContext`, adam, Nov 10): numbers often sit in
/// earlier answers of the same chat ("population of Brazil", then "and Russia?"). With no model: from the last few
/// earlier answers that share the topic, keep the sentences that hold a number, deduplicated and short, each with the
/// question it answered. The grounding check accepts a number from any of them, never one from none.
public enum VisualContext {
    public struct Exchange: Equatable, Sendable {
        public var question: String
        public var answer: String
        public init(_ question: String, _ answer: String) { self.question = question; self.answer = answer }
    }

    /// `facts`: "question — sentence" lines for the prompt; `sourceText`: the same sentences, for the grounding check.
    public struct Earlier: Equatable, Sendable {
        public var facts: [String]
        public var sourceText: String
        public init(_ facts: [String], _ sourceText: String) { self.facts = facts; self.sourceText = sourceText }
        public var isEmpty: Bool { facts.isEmpty }
        public static let none = Earlier([], "")
    }

    public static let maxExchanges = 5
    public static let maxFacts = 12
    public static let maxChars = 1500

    /// The earlier facts for a visual of `current`, from `previous` (oldest first, the current exchange not included):
    /// only exchanges that share at least two content words with the current question and answer, newest first, then
    /// their sentences with a digit, at most `maxFacts` and `maxChars` in all.
    public static func earlier(_ current: Exchange, _ previous: [Exchange]) -> Earlier {
        let topic = words(current.question + " " + current.answer)
        let inAnswer = fold(current.answer)
        var seen = Set<String>()
        var facts: [String] = []
        var sentences: [String] = []
        var chars = 0
        for e in previous.reversed().prefix(maxExchanges) {
            if words(e.question + " " + e.answer).intersection(topic).count < 2 { continue }
            for s in sentencesWithNumbers(e.answer) {
                let key = spaces.replace(fold(s), with: " ")
                if !seen.insert(key).inserted || inAnswer.contains(key) { continue }
                // One line each, newlines collapsed: an earlier question can't forge a "ANSWER:" line (validator).
                let line = "\(spaces.replace(e.question, with: " ").kotlinTrim().u16Take(80)) — \(spaces.replace(s, with: " "))"
                if facts.count >= maxFacts || chars + line.u16 > maxChars { break }
                facts.append(line); sentences.append(s); chars += line.u16
            }
        }
        return Earlier(facts, sentences.joined(separator: "\n"))
    }

    public static let maxSourceFacts = 10
    public static let maxSourceChars = 1200

    /// The answer's own sources (adam, Nov 10: "does we have a brazil source with area?"): the sentences with a number from
    /// the passages the answer was written from, those sharing the most words with the question and the answer first,
    /// deduplicated, not already in the answer, at most `maxSourceFacts` and `maxSourceChars`. A number the model takes
    /// from them is backed, so it stays.
    public static func fromSources(_ question: String, _ answer: String, _ passages: [(title: String, body: String)]) -> Earlier {
        let topic = words(question + " " + answer)
        let inAnswer = fold(answer)
        var seen = Set<String>()
        var fresh: [(String, String)] = []
        for p in passages {
            for s in sentencesWithNumbers(p.body) {
                let k = spaces.replace(fold(s), with: " ")
                if seen.insert(k).inserted && !inAnswer.contains(k) { fresh.append((p.title, s)) }
            }
        }
        // Most shared words first; a stable sort, as Kotlin's sortedByDescending.
        let shared = fresh.map { words($0.0 + " " + $0.1).intersection(topic).count }
        let order = fresh.indices.sorted { a, b in shared[a] != shared[b] ? shared[a] > shared[b] : a < b }
        let candidates = order.map { fresh[$0] }
        var facts: [String] = []
        var sentences: [String] = []
        var chars = 0
        for (title, s) in candidates {
            let line = "\(spaces.replace(title, with: " ").u16Take(60)) — \(spaces.replace(s, with: " "))"
            if facts.count >= maxSourceFacts || chars + line.u16 > maxSourceChars { break }
            facts.append(line); sentences.append(s); chars += line.u16
        }
        return Earlier(facts, sentences.joined(separator: "\n"))
    }

    /// The user message for the visual's model: the question, the answer, then the earlier facts and the facts from the
    /// answer's sources when there are any.
    public static func prompt(_ question: String, _ answer: String, _ earlier: Earlier, _ sources: Earlier = .none) -> String {
        var s = "QUESTION: \(question.u16Take(400))\n\nANSWER:\n\(answer.u16Take(3000))"
        if !earlier.isEmpty {
            s += "\n\nEARLIER IN THIS CHAT (facts from earlier answers; use them only for the same visual as the ANSWER):\n"
            for f in earlier.facts { s += "- \(f)\n" }
        }
        if !sources.isEmpty {
            s += "\n\nFROM THE SOURCES (facts from the articles this ANSWER used; use them only to fill a value the ANSWER's visual needs):\n"
            for f in sources.facts { s += "- \(f)\n" }
        }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return s
    }

    private static let spaces = Rx.java(#"\s+"#)
    private static let citeMark = Rx.java(#"\s*\[\d{1,3}\]"#)
    private static let sentenceBreak = Rx.java(#"(?<=[.!?])\s+|\n+"#)
    private static let letters4 = Rx(#"\p{L}{4,}"#)

    /// Sentences that hold a digit, cut at . ! ? or a line break; citation marks like [3] removed.
    public static func sentencesWithNumbers(_ text: String) -> [String] {
        sentenceBreak.split(citeMark.replace(text, with: ""))
            .map { s in
                var t = Substring(s.kotlinTrim())
                while let f = t.first, f == "-" || f == "•" || f == "*" || f == " " { t.removeFirst() }
                return String(t)
            }
            .filter { s in (8...300).contains(s.u16) && s.unicodeScalars.contains { $0.properties.generalCategory == .decimalNumber } }
    }

    private static let stop: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "what", "how", "why", "which", "are", "was", "were", "about",
        "de", "da", "do", "das", "dos", "para", "com", "por", "que", "qual", "como", "uma", "mais", "also",
    ]

    private static func fold(_ s: String) -> String { VisualCheck.fold(s) }

    private static func words(_ s: String) -> Set<String> {
        let f = fold(s)
        return Set(letters4.matches(in: f).map { m -> String in
            let w = (f as NSString).substring(with: m.range)
            return w.hasSuffix("s") ? String(w.dropLast()) : w
        }.filter { !stop.contains($0) })
    }
}
