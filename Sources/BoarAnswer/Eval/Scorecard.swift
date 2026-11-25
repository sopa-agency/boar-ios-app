import BoarCore
import BoarRAG
import BoarRouting
import Foundation

/// The scorecard at the end of every run (android engine/eval `Scorecard.kt`, v2.0.0; adam, Nov 14: "we could have a score
/// and topics. like, bad on this, good on those"; t9 0521 item 4): one line per topic, passed over checked by its rules,
/// next to the previous run of the same level and topic (up, down, same); one line per model and pass with its first word,
/// whole answer and peak memory. The computer scores only what a rule can check; the rest is "to read". Pure: rows in,
/// scorecard out.
public enum Scorecard {
    /// known: failed, with a known issue (TopicQuestion.knownIssue); skipped: its plugin was off in that run.
    public enum Verdict: String, Sendable, Equatable { case pass, fail, toRead, known, skipped }
    public enum Trend: String, Sendable, Equatable { case up, down, same }

    /// One rule on one answer: `ok` nil when the row can't tell (an old run without the field).
    public struct Check: Sendable, Equatable {
        public var rule: String
        public var ok: Bool?
        public var detail: String
        public init(_ rule: String, _ ok: Bool?, _ detail: String = "") { self.rule = rule; self.ok = ok; self.detail = detail }
    }

    public struct RowResult: Sendable, Equatable {
        public var queryId: String
        public var topic: String
        public var modelId: String?
        public var pass: String
        public var verdict: Verdict
        public var checks: [Check]
        public var toRead: String
    }

    public struct TopicLine: Sendable, Equatable {
        public var topic: String
        public var passed: Int
        public var checked: Int
        public var toRead: Int
        public var total: Int
        /// The previous run's passed and checked for this topic, when it ran it.
        public var previousPassed: Int?
        public var previousChecked: Int?
        public var trend: Trend?
        /// Failures with a known issue, and questions skipped (their plugin off): counted apart from `checked`.
        public var known = 0
        public var skipped = 0
    }

    public struct ModelLine: Sendable, Equatable {
        public var modelId: String
        public var pass: String
        public var answers: Int
        /// Medians: the first word, the whole answer.
        public var firstWordMs: Double?
        public var wholeAnswerMs: Double?
        public var peakRssBytes: Double?
    }

    public struct Card: Sendable, Equatable {
        public var topics: [TopicLine]
        public var models: [ModelLine]
        public var rows: [RowResult]
    }

    /// A row's topic: the one it says (rows since presets carry it), else the first topic holding its question (old runs:
    /// the fixed set's ids are "core", the language set's "portuguese"), else "custom".
    public static func topicOf(_ row: JSONValue, _ topics: [BenchTopic]) -> String {
        if let t = row.str("topic") { return t }
        let id = row.str("queryId") ?? ""
        let ordered = topics.filter { $0.id == BenchPresets.core } + topics.filter { $0.id != BenchPresets.core }
        return ordered.first { $0.question(id) != nil }?.id ?? "custom"
    }

    public static func judge(_ row: JSONValue, _ topics: [String: BenchTopic]) -> RowResult {
        // Kotlin's map keeps the files' order; ours is sorted by id, so "first holding the question" is the same every time.
        let topic = topicOf(row, topics.keys.sorted().compactMap { topics[$0] })
        let queryId = row.str("queryId") ?? ""
        let q = topics[topic]?.question(queryId)
        var checks: [Check] = []
        // Its plugin off in this run (rows say which were on): not asked, said so.
        if let q, let lab = q.needsLab {
            let on = row["labsOn"]?.arrayValue.map { _ in row.list("labsOn") }
            if on == nil || !on!.contains(lab) {
                return RowResult(queryId: queryId, topic: topic, modelId: row.str("modelId"), pass: BenchPresets.passKey(row), verdict: .skipped,
                                 checks: [Check("needsLab", nil, "\(lab) off")], toRead: q.toRead)
            }
        }
        let outcome = row.str("outcome")
        if outcome != "success" { checks.append(Check("answered", false, outcome ?? "no outcome")) }
        if let rules = q?.rules, !rules.isEmpty { checks += check(row, rules) }
        let known = checks.filter { $0.ok != nil }
        let verdict: Verdict =
            if known.contains(where: { $0.ok == false }) && q?.knownIssue != nil { .known }
            else if known.contains(where: { $0.ok == false }) { .fail }
            else if known.isEmpty { .toRead }
            else { .pass }
        return RowResult(queryId: queryId, topic: topic, modelId: row.str("modelId"), pass: BenchPresets.passKey(row), verdict: verdict,
                         checks: checks, toRead: q?.toRead ?? "")
    }

    // Java's \d is ASCII only.
    private static let citation = try! NSRegularExpression(pattern: #"\[([0-9]{1,3})\]"#)
    private static let number = try! NSRegularExpression(pattern: #"(?<![0-9.,])[0-9]+(?:[.,][0-9]+)*"#)
    private static let thousandsSpace = try! NSRegularExpression(pattern: #"(?<=[0-9]) (?=[0-9]{3}\b)"#)

    private static func matches(_ re: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
        re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// The numbers in `text`, read the way the calculators read them (its own marks first, then its language).
    public static func numbersIn(_ text: String) -> [Double] {
        let spaced = text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        // "8 849 m": a space between thousands.
        let t = thousandsSpace.stringByReplacingMatches(in: spaced, range: NSRange(location: 0, length: (spaced as NSString).length), withTemplate: "")
        let pt = AnswerLanguage.clear(t) == .pt
        let comma = Calculators.readsComma(t, pt: pt)
        let ns = t as NSString
        return matches(number, t).compactMap { m in
            var raw = ns.substring(with: m.range)
            while let last = raw.last, last == "." || last == "," { raw.removeLast() }
            let v = Calculators.parseNumber(raw, pt: comma)
            return v.isFinite ? v : nil
        }
    }

    private static func near(_ n: Double, _ rule: NumberRule) -> Bool { abs(n - rule.value) <= abs(rule.value) * rule.tolerance + 1e-9 }

    private static func cardName(_ c: CardRules.Card) -> String {
        switch c {
        case .steps: "steps"
        case .table: "table"
        case .facts: "facts"
        case .compare: "compare"
        case .chart: "chart"
        }
    }

    /// Kotlin `Double.toString` for a rule's label: "8849.0".
    private static func label(_ n: NumberRule) -> String { n.label.isEmpty ? "\(n.value)" : n.label }

    public static func check(_ row: JSONValue, _ r: TopicRules) -> [Check] {
        let answer = row.str("answer") ?? ""
        let lower = answer.lowercased()
        func has(_ s: String) -> Bool { lower.contains(s.lowercased()) }
        let head = String(answer.prefix(80))
        var out: [Check] = []
        if let want = r.tool {
            let tools = row.str("tool")?.split(separator: "+", omittingEmptySubsequences: false).map(String.init) ?? []
            let codes = row.list("reasonCodes")
            out.append(Check("tool", tools.contains(want) || codes.contains("answer:\(want)"), row.str("tool") ?? "no plugin answered"))
        }
        if r.noTool {
            out.append(Check("noTool", row.str("tool") == nil && !row.list("reasonCodes").contains { $0.hasPrefix("answer:") }, row.str("tool") ?? "the model answered"))
        }
        if let s = r.answerIs { out.append(Check("answerIs", answer.trimmingCharacters(in: .whitespacesAndNewlines) == s.trimmingCharacters(in: .whitespacesAndNewlines), head)) }
        if let s = r.answerStartsWith {
            out.append(Check("answerStartsWith", String(answer.drop { $0.isWhitespace }).hasPrefix(s), head))
        }
        for s in r.answerHas { out.append(Check("answerHas", has(s), s)) }
        if !r.answerHasAny.isEmpty { out.append(Check("answerHasAny", r.answerHasAny.contains(where: has), r.answerHasAny.joined(separator: " / "))) }
        for g in r.answerHasEach where !g.isEmpty { out.append(Check("answerHasEach", g.contains(where: has), g.joined(separator: " / "))) }
        for s in r.answerHasNot { out.append(Check("answerHasNot", !has(s), s)) }
        if let want = r.language {
            let got: String? = switch AnswerLanguage.clear(answer) {
            case .en?: "en"
            case .pt?: "pt"
            case .other?: "other"
            case nil: nil
            }
            out.append(Check("language", got == want.lowercased(), got ?? "unclear"))
        }
        let sources = row.list("retrievedTitles")
        if r.citesOnlyRealSources {
            let ns = answer as NSString
            let cited = Set(matches(citation, answer).compactMap { Int(ns.substring(with: $0.range(at: 1))) })
            let bad = cited.filter { $0 < 1 || $0 > sources.count }.sorted()
            out.append(Check("citesOnlyRealSources", bad.isEmpty,
                             bad.isEmpty ? "\(cited.count) cited of \(sources.count)" : "[\(bad.map(String.init).joined(separator: "], ["))] with \(sources.count) sources"))
        }
        for s in r.sourcesNot { out.append(Check("sourcesNot", !sources.contains { $0.range(of: s, options: .caseInsensitive) != nil }, s)) }
        if r.noFileSources {
            // Rows since presets list the user's own files among the sources (fileSources); an older row can't tell.
            let files = row["fileSources"]?.arrayValue
            out.append(Check("noFileSources", files.map(\.isEmpty), files.map { _ in row.list("fileSources").joined(separator: ", ") } ?? "not recorded"))
        }
        if !r.numbers.isEmpty || !r.numbersAny.isEmpty || !r.numbersNot.isEmpty {
            let found = numbersIn(answer)
            for n in r.numbers { out.append(Check("numbers", found.contains { near($0, n) }, label(n))) }
            if !r.numbersAny.isEmpty {
                out.append(Check("numbersAny", r.numbersAny.contains { n in found.contains { near($0, n) } }, r.numbersAny.map(label).joined(separator: " / ")))
            }
            for n in r.numbersNot { out.append(Check("numbersNot", !found.contains { near($0, n) }, label(n))) }
        }
        if !r.cards.isEmpty || r.minChartPoints != nil {
            let cards = CardRules.find(row.str("query") ?? "", answer)
            let names = cards.map(cardName)
            for c in r.cards { out.append(Check("cards", names.contains(c), "\(c) in [\(names.joined(separator: ", "))]")) }
            if let min = r.minChartPoints {
                let points = cards.compactMap { if case .chart(let p, _, _) = $0 { p.count } else { nil } }.max() ?? 0
                out.append(Check("minChartPoints", points >= min, "\(points) points"))
            }
        }
        if r.keptShort { out.append(Check("keptShort", row.str("personalityId") == "succinct", row.str("personalityId") ?? "?")) }
        return out
    }

    public static func of(_ rows: [JSONValue], topics: [String: BenchTopic], previous: [JSONValue]? = nil) -> Card {
        let results = rows.map { judge($0, topics) }
        let before = previous.map { p in Dictionary(grouping: p.map { judge($0, topics) }, by: \.topic) }
        let lines = grouped(results, by: \.topic).map { topic, rs in
            let passed = rs.count { $0.verdict == .pass }
            // Checked = pass or fail; known failures and skipped questions are counted apart, so the trend shows regressions.
            let checked = rs.count { $0.verdict == .pass || $0.verdict == .fail }
            let prev = before?[topic]
            let pPassed = prev?.count { $0.verdict == .pass }
            let pChecked = prev?.count { $0.verdict == .pass || $0.verdict == .fail }
            return TopicLine(topic: topic, passed: passed, checked: checked, toRead: rs.count { $0.verdict == .toRead }, total: rs.count,
                             previousPassed: pPassed, previousChecked: pChecked, trend: trend(passed, checked, pPassed, pChecked),
                             known: rs.count { $0.verdict == .known }, skipped: rs.count { $0.verdict == .skipped })
        }
        struct Key: Hashable { let model: String; let pass: String }
        let models = grouped(rows, by: { Key(model: $0.str("modelId") ?? $0.str("configId") ?? "", pass: BenchPresets.passKey($0)) }).map { k, rs in
            let done = rs.filter { $0.str("outcome") == "success" }
            return ModelLine(modelId: k.model, pass: k.pass, answers: rs.count, firstWordMs: EvalScore.median(done.compactMap { $0.num("ttftMs") }),
                             wholeAnswerMs: EvalScore.median(done.compactMap { $0.num("totalLatencyMs") }),
                             peakRssBytes: rs.compactMap { $0.num("peakRssBytes") }.max())
        }
        return Card(topics: lines, models: models, rows: results)
    }

    /// Kotlin `groupBy`: groups in the order their first member comes.
    private static func grouped<T, K: Hashable>(_ items: [T], by key: (T) -> K) -> [(K, [T])] {
        var order: [K] = []
        var groups: [K: [T]] = [:]
        for item in items {
            let k = key(item)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(item)
        }
        return order.map { ($0, groups[$0]!) }
    }

    /// Up, down or same by the share passed; nil when either run checked nothing in the topic.
    public static func trend(_ passed: Int, _ checked: Int, _ prevPassed: Int?, _ prevChecked: Int?) -> Trend? {
        guard let prevPassed, let prevChecked, prevChecked != 0, checked != 0 else { return nil }
        let now = Double(passed) / Double(checked)
        let then = Double(prevPassed) / Double(prevChecked)
        if abs(now - then) < 1e-9 { return .same }
        return now > then ? .up : .down
    }

    /// The scorecard as text, for the log and the saved file: "plugins      9/10 (was 8/10) up · 0 to read".
    public static func text(_ card: Card) -> String {
        var s = ""
        for t in card.topics {
            s += t.topic.padding(toLength: max(12, t.topic.count), withPad: " ", startingAt: 0) + " \(t.passed)/\(t.checked)"
            if let pc = t.previousChecked { s += " (was \(t.previousPassed.map(String.init) ?? "null")/\(pc))" }
            if let tr = t.trend { s += " " + tr.rawValue }
            s += " · \(t.toRead) to read"
            if t.known > 0 { s += " · \(t.known) known issues" }
            if t.skipped > 0 { s += " · \(t.skipped) skipped (plugin off)" }
            s += "\n"
        }
        for m in card.models {
            s += "\(m.modelId) · \(m.pass): \(m.answers) answers, first word \(secs(m.firstWordMs)), whole answer \(secs(m.wholeAnswerMs)), peak "
            s += (m.peakRssBytes.map { String(format: "%.2f GB", locale: Locale(identifier: "en_US_POSIX"), $0 / 1e9) } ?? "—") + "\n"
        }
        return s
    }

    private static func secs(_ ms: Double?) -> String {
        ms.map { String(format: "%.1f s", locale: Locale(identifier: "en_US_POSIX"), $0 / 1000) } ?? "—"
    }
}
