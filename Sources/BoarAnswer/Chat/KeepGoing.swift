import Foundation

/// "Keep going" (android `KeepGoing`, adam Nov 13-14; t9 0235): under the latest answer, outside its card, up to three
/// faint bubbles on the user's side. One step at most (the next rung of the ladder Quick › Detailed › Research, or
/// "Ask BOAR" after a plugin's instant answer), then follow-up questions from the answer's own sources. No model call:
/// what the answer already has.
public enum KeepGoing {
    /// `continue` (adam, 16 Nov): sends "Continue" as a message, so BOAR goes on from its last answer in the same style
    /// (a meta follow-up, `DeepResearch.isMetaFollowUp`). `deeper` is no longer offered; it stays so older chats' bubbles
    /// still read "Go deeper".
    public enum Step: String, Sendable, CaseIterable {
        case deeper, `continue`, research, ask

        /// The key kept in a user message's meta (android `Step.key`; the ask step's key is "ask").
        public var key: String { rawValue }

        public static func of(_ key: String?) -> Step? { key.flatMap(Step.init(rawValue:)) }
    }

    /// What the answer was, from its receipt and the chat.
    public struct Answer: Sendable {
        /// Failed, stopped or timed out: nothing to offer but the repair inside the card.
        public var broken: Bool
        /// A plugin's instant answer (no model ran), and whether the user may ask the model instead (not the CO answer).
        public var instant: Bool
        public var canBypass: Bool
        /// The style it was written in: "succinct", "detailed", "personal", "custom".
        public var style: String?
        public var deepResearch: Bool
        /// Cut at the token limit: the repair is in the card.
        public var cut: Bool
        /// The app kept it short on purpose (a health or seed-phrase question): no "deeper".
        public var keptShort: Bool
        public var hasSources: Bool

        public init(broken: Bool = false, instant: Bool = false, canBypass: Bool = false, style: String? = nil, deepResearch: Bool = false,
                    cut: Bool = false, keptShort: Bool = false, hasSources: Bool = false) {
            self.broken = broken
            self.instant = instant
            self.canBypass = canBypass
            self.style = style
            self.deepResearch = deepResearch
            self.cut = cut
            self.keptShort = keptShort
            self.hasSources = hasSources
        }
    }

    public struct Next: Sendable, Equatable {
        public var step: Step?
        public var followUps: [String]

        public init(step: Step?, followUps: [String]) {
            self.step = step
            self.followUps = followUps
        }
    }

    public static let max = 3

    /// Follow-up questions are off until adam reads the table (t9 0235 item 7: "if they read poorly, the bubbles ship with
    /// the steps only"). On the F3's 56 real answers they did: "Purified water" for a question on purifying water,
    /// "Cutlet" for bread, "Nature reserve" for "natureza", and a title from the user's own files.
    public static let followUpsOn = false
    public static let maxFollowUps = 2

    /// The table of t9 0235, row by row.
    public static func of(_ a: Answer, followUps: [String]) -> Next {
        if a.broken { return Next(step: nil, followUps: []) }
        if a.instant { return Next(step: a.canBypass ? .ask : nil, followUps: []) }
        let step: Step? = if a.cut || a.deepResearch || a.keptShort {
            nil
        } else if a.style == "succinct" {
            .continue
        } else if a.style == "detailed" {
            .research
        } else {
            nil // Personal Files, Custom: no ladder.
        }
        var seen = Set<String>()
        let unique = followUps.filter { seen.insert($0).inserted }
        let asks = a.hasSources ? Array(unique.prefix(maxFollowUps)) : []
        return Next(step: step, followUps: Array(asks.prefix(Swift.max(0, max - (step != nil ? 1 : 0)))))
    }

    /// The ladder under the step's verb: the rungs done filled ("● Quick › ○ Detailed › ○ Research").
    public static func rungsDone(_ step: Step) -> Int {
        switch step {
        case .deeper: 1
        case .continue: 0
        case .research: 2
        case .ask: 1
        }
    }

    /// Whether the step shows the style ladder under its verb: Continue changes no style, so it has none.
    public static func showsLadder(_ step: Step) -> Bool { step != .continue }

    /// What the next question carries (android's `stepOnce`, `styleOnce`, `deepOnce` and `skipToolsOnce`): for that question
    /// only. The user's style and the Deep Research switch stay as set.
    public struct Overrides: Sendable, Equatable {
        public var step: Step?
        public var style: String?
        public var deep: Bool?
        public var skipTools = false

        public init(step: Step? = nil, style: String? = nil, deep: Bool? = nil, skipTools: Bool = false) {
            self.step = step
            self.style = style
            self.deep = deep
            self.skipTools = skipTools
        }

        /// Take what a question carries and leave nothing behind (android `send` reads each and clears it).
        public mutating func take() -> Overrides {
            defer { self = Overrides() }
            return self
        }

        /// The held question went with its note (closed, or the catalog opened instead, or the model failed to load): what
        /// was set for it goes too, or the next typed question would run in Detailed or Deep Research, skip the plugins and
        /// show a step's verb (android `dropOnce`, validator A-2). iOS has no bypassed-plugin context to clear.
        public mutating func drop() { self = Overrides() }

        /// What a step sets for the question it repeats: Go deeper in Detailed, Research this with Deep Research. Continue
        /// is its own message and Ask BOAR skips the plugins.
        public static func of(_ step: Step) -> Overrides {
            switch step {
            case .deeper: Overrides(step: step, style: "detailed")
            case .research: Overrides(step: step, deep: true)
            case .ask: Overrides(step: step, skipTools: true)
            case .continue: Overrides(step: step)
            }
        }
    }

    /// The user message's meta for a step (android `stepMeta`): `{"step": "<key>"}`.
    public static func stepMeta(_ step: Step) -> String {
        "{\"step\":\"\(step.key)\"}"
    }

    /// The step a user message records, if any (android `stepFromMeta`).
    public static func step(fromMeta meta: String?) -> Step? {
        guard let meta, let data = meta.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let key = o["step"] as? String else { return nil }
        return Step.of(key)
    }
}

/// Follow-up questions with no model call (android `FollowUps`, coder's plan of Nov 12): another source's title ("Tell me
/// more about <title>"), then a named thing in a cited passage that is not in the question ("What is <thing>?"). Never the
/// question's own topic, no duplicates, two at most. Pure: text in, questions out.
public enum FollowUps {
    /// `fromPack`: a knowledge pack's article; never the user's own files (their names stay theirs).
    public struct Source: Sendable {
        public var title: String
        public var body: String
        public var cited: Bool
        public var fromPack: Bool

        public init(title: String, body: String, cited: Bool, fromPack: Bool = true) {
            self.title = title
            self.body = body
            self.cited = cited
            self.fromPack = fromPack
        }
    }

    public static func pick(_ question: String, _ sources: [Source], pt: Bool, max: Int = KeepGoing.maxFollowUps) -> [String] {
        let q = norm(question)
        var out: [String] = []
        var seen = Set<String>()
        // 1. Another source's title, cited ones first; a title the question already names is its topic.
        // Only what the answer cites, only from the packs: an uncited passage was often off-topic ("Cutlet" for bread).
        let usable = sources.filter { $0.cited && $0.fromPack && !fileLike(in: $0.title) }
        for s in usable {
            let t = cleanTitle(s.title)
            let k = norm(t)
            if t.isEmpty || seen.contains(k) || mentioned(k, q) { continue }
            seen.insert(k)
            out.append(pt ? "Fale mais sobre \(t)" : "Tell me more about \(t)")
            break
        }
        // 2. A named thing in a cited passage, not in the question, not a source already offered.
        for s in usable {
            for name in names(s.body) {
                let k = norm(name)
                if seen.contains(k) || mentioned(k, q) || k.count < 4 { continue }
                seen.insert(k)
                out.append(pt ? "O que é \(name)?" : "What is \(name)?")
                break
            }
            if out.count >= max { break }
        }
        return Array(out.prefix(max))
    }

    /// "Mercury (planet)" -> "Mercury"; a pack's "Title — section" -> "Title".
    public static func cleanTitle(_ t: String) -> String {
        let head = t.components(separatedBy: " — ").first ?? t
        return head.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"\p{M}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A file's name, not an article's: "eBook_investimentos (part 16/17)".
    private static func fileLike(in title: String) -> Bool {
        title.range(of: #"_|\(part \d+/\d+\)|\.(pdf|txt|md|docx?|csv)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Every word of the name is in the question, by its stem ("purified" and "purify"): the question's own topic.
    private static func mentioned(_ name: String, _ q: String) -> Bool {
        let qw = Set(q.split(separator: " ", omittingEmptySubsequences: false).filter { $0.count > 2 }.map(stem))
        let words = name.split(separator: " ", omittingEmptySubsequences: false).filter { $0.count > 2 }.map(stem)
        return !words.isEmpty && words.allSatisfy { qw.contains($0) }
    }

    private static func stem(_ w: Substring) -> String { String(w.prefix(5)) }

    private static let namePattern = try! NSRegularExpression(pattern: #"\b(\p{Lu}[\p{L}'-]+(?:\s+(?:of|de|da|do|the|von|van)?\s*\p{Lu}[\p{L}'-]+){0,3})"#)
    private static let stop: Set<String> = ["The", "This", "That", "These", "Those", "It", "In", "On", "At", "A", "An", "He", "She", "They", "We", "I", "His", "Her", "Its",
                                            "O", "A", "Os", "As", "Um", "Uma", "Ele", "Ela", "Em", "No", "Na", "De", "Da", "Do", "Se", "Por", "Para", "Com", "Mas", "And", "But", "However", "Also", "When", "After", "Before"]

    /// Capitalised names in a passage, not at the start of a sentence unless they run over two words.
    public static func names(_ body: String) -> [String] {
        let text = body as NSString
        var out: [String] = []
        for m in namePattern.matches(in: body, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let first = name.components(separatedBy: " ").first ?? name
            if stop.contains(first) { continue }
            let before = text.substring(to: m.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            let sentenceStart = before.isEmpty || ".!?:\n".contains(before.last!)
            if sentenceStart && !name.contains(" ") { continue }
            out.append(name)
        }
        return out
    }
}
