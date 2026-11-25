import BoarCore
import Foundation

/// A label and its number in a series; Kotlin's `Pair<String, Double>`.
public struct VisualItem: Equatable, Hashable, Sendable {
    public var label: String
    public var value: Double
    public init(_ label: String, _ value: Double) { self.label = label; self.value = value }
}

/// Boar Canvas's merged visual (android `Visual`; cards and widgets in one, adam, Nov 10): the model reads a finished
/// answer and returns ONE JSON object, the data and a suggested type; the app checks every number and label against the
/// answer and draws it with its own components. The model never computes: percentages, totals and axes are the app's
/// (`VisualScale`).
///
///     {"type":"table","title":"…","columns":["…","…"],"rows":[["…","…"]]}
///     {"type":"bars"|"line"|"share","title":"…","unit":"…","items":[{"label":"…","value":12.5}]}
///     {"type":"steps","title":"…","steps":["…","…"]}
///     {"type":"compare","title":"…","items":[{"name":"…","points":["…","…"]}]}
///     {"type":"facts","title":"…","facts":[{"label":"…","value":"…"}]}
///     {"type":"none"}
///
/// "pie" is read as "share". The interactive kinds (timeline, slider, quiz, converter) are reserved: read and refused.
public enum Visual: Equatable, Sendable {
    case table(Table)
    /// One list of labelled numbers, drawn as `kind`; the same data can be shown as any kind `VisualScale.kinds` allows.
    case series(Series)
    case steps(Steps)
    case compare(Compare)
    case facts(Facts)

    public struct Table: Equatable, Sendable {
        public var title: String
        public var columns: [String]
        public var rows: [[String]]
        public init(_ title: String, _ columns: [String], _ rows: [[String]]) { self.title = title; self.columns = columns; self.rows = rows }
    }

    public struct Series: Equatable, Sendable {
        public var title: String
        public var kind: SeriesKind
        public var unit: String?
        public var items: [VisualItem]
        public init(_ title: String, _ kind: SeriesKind, _ unit: String?, _ items: [VisualItem]) {
            self.title = title; self.kind = kind; self.unit = unit; self.items = items
        }
    }

    public struct Steps: Equatable, Sendable {
        public var title: String
        public var steps: [String]
        public init(_ title: String, _ steps: [String]) { self.title = title; self.steps = steps }
    }

    public struct Compare: Equatable, Sendable {
        public var title: String
        public var items: [CardSide]
        public init(_ title: String, _ items: [CardSide]) { self.title = title; self.items = items }
    }

    public struct Facts: Equatable, Sendable {
        public var title: String
        public var facts: [CardFact]
        public init(_ title: String, _ facts: [CardFact]) { self.title = title; self.facts = facts }
    }

    public enum SeriesKind: String, Sendable, CaseIterable { case bars = "BARS", line = "LINE", share = "SHARE" }

    public var title: String {
        switch self {
        case .table(let t): t.title
        case .series(let s): s.title
        case .steps(let s): s.title
        case .compare(let c): c.title
        case .facts(let f): f.title
        }
    }

    public enum Parsed: Equatable, Sendable {
        /// `leftOut`: what was taken out because none of the texts has it (a number, a name), shown under the visual.
        case ok(Visual, leftOut: [String])
        /// `detail`: what failed, for the eval and the log (a number, a label); never shown as the answer.
        case rejected(Reason, detail: String?)
    }

    /// nothing: the model said a visual wouldn't help. reserved: an interactive kind not built yet. inventedNumbers and
    /// ungroundedLabels: something not in the answer (or the user's own message). badShare: parts that can't make a whole.
    public enum Reason: String, Sendable, CaseIterable {
        case noJson = "NO_JSON", unknownType = "UNKNOWN_TYPE", reserved = "RESERVED", empty = "EMPTY", inventedNumbers = "INVENTED_NUMBERS"
        case ungroundedLabels = "UNGROUNDED_LABELS", unpaired = "UNPAIRED", badShare = "BAD_SHARE", nothing = "NOTHING"
    }

    public static let maxRows = 20
    public static let maxColumns = 6
    public static let maxItems = 12
    public static let maxShareParts = 8
    public static let maxText = 160
    public static let reservedKinds: Set<String> = ["timeline", "slider", "quiz", "converter"]

    /// The first JSON object in the model's `raw` reply (after any reasoning, inside a fence or a sentence), checked
    /// against `answer` and, for numbers the user typed, `userText`.
    public static func parse(_ raw: String, answer: String, userText: String = "") -> Parsed {
        guard let o = firstObject(raw.kotlinAfterLast("</think>")) else { return .rejected(.noJson, detail: nil) }
        let title = text(o, "title") ?? ""
        guard let type = text(o, "type")?.lowercased().kotlinTrim() else { return .rejected(.unknownType, detail: nil) }
        let visual: Visual
        switch type {
        case "none":
            return .rejected(.nothing, detail: nil)
        case _ where reservedKinds.contains(type):
            return .rejected(.reserved, detail: type)
        case "table":
            let columns = Array(strings(o, "columns").prefix(maxColumns))
            let rows = (o["rows"]?.arrayValue ?? []).compactMap { r in r.arrayValue?.map(cell) }
                .filter { r in r.contains { !$0.allSatisfy(\.isWhitespace) } }
                .prefix(maxRows)
                .map { r in Array((r + Array(repeating: "", count: columns.count)).prefix(columns.count)) }
            if columns.isEmpty || rows.isEmpty { return .rejected(.empty, detail: nil) }
            visual = .table(Table(title, columns, Array(rows)))
        case "bars", "bar", "line", "share", "pie":
            let kind: SeriesKind = switch type {
            case "line": .line
            case "share", "pie": .share
            default: .bars
            }
            let source = o["items"]?.arrayValue ?? o["data"]?.arrayValue ?? []
            let items: [VisualItem] = source.compactMap { i in
                guard case .object = i else { return nil }
                // A value written as text ("3,5") is read by its form (VisualCheck.readings), never the English way first.
                let v: Double?
                switch i["value"] {
                case .string(let s)?:
                    let vs = VisualCheck.valuesOf(s)
                    v = vs.count == 1 ? vs[0] : nil
                case .int(let n)?: v = Double(n)
                case .double(let d)?: v = d
                default: v = nil
                }
                guard let v, let label = text(i, "label") else { return nil }
                return VisualItem(label, v)
            }.filter { $0.value.isFinite }
            // More parts than a pie can show is refused, not cut and drawn as if the rest were the whole (V-7).
            if kind == .share && items.count > maxShareParts { return .rejected(.badShare, detail: "\(items.count)") }
            let kept = Array(items.prefix(maxItems))
            if kept.count < 2 { return .rejected(.empty, detail: nil) }
            if kind == .share && !VisualScale.canShare(kept.map(\.value)) { return .rejected(.badShare, detail: nil) }
            let unit = text(o, "unit").flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
            visual = .series(Series(title, kind, unit, kept))
        case "steps":
            let steps = Array(strings(o, "steps").prefix(maxItems))
            if steps.count < 2 { return .rejected(.empty, detail: nil) }
            visual = .steps(Steps(title, steps))
        case "compare":
            let items = (o["items"]?.arrayValue ?? []).compactMap { i -> CardSide? in
                guard case .object = i, let name = text(i, "name") else { return nil }
                return CardSide(name, Array(strings(i, "points").prefix(maxItems)))
            }.filter { !$0.points.isEmpty }.prefix(4)
            if items.count < 2 { return .rejected(.empty, detail: nil) }
            visual = .compare(Compare(title, Array(items)))
        case "facts":
            let facts = (o["facts"]?.arrayValue ?? []).compactMap { f -> CardFact? in
                guard case .object = f, let l = text(f, "label"), let v = text(f, "value") else { return nil }
                return CardFact(l, v)
            }.prefix(maxItems)
            if facts.isEmpty { return .rejected(.empty, detail: nil) }
            visual = .facts(Facts(title, Array(facts)))
        default:
            return .rejected(.unknownType, detail: type)
        }
        // What isn't in the texts comes out (an item, a row or column, a line); refused only when too little is left.
        let pruned = VisualCheck.prune(visual, answer: answer, userText: userText)
        if let v = pruned.visual { return .ok(v, leftOut: pruned.leftOut) }
        return .rejected(pruned.reason ?? .empty, detail: pruned.leftOut.first)
    }

    /// The prompt: the model extracts and picks, the app computes and draws. "none" is a fine reply, better than a forced
    /// visual. Short texts keep the JSON small (a 1.7B model writes 150 tokens in 11 to 15 s on the X6).
    public static let prompt = "You extract structured data from an encyclopedia ANSWER into ONE visual for a phone screen. "
        + "Reply with ONE JSON object and nothing else.\n"
        // Rules before the examples: a 1.7B model weighs what it reads first (X6, Nov 10: a 6-column table filled from
        // memory, and an area of 8.5 under "km²" that meant 8.5 million km²).
        + "STRICT RULES:\n"
        + "1. Use ONLY facts and numbers written in the ANSWER (or EARLIER IN THIS CHAT or FROM THE SOURCES), copied exactly as written there.\n"
        + "2. NEVER add, invent, estimate, round, convert or compute a number, and never fill missing data from memory "
        + "(no totals, no percentages: the app does that).\n"
        + "3. Units: write the unit exactly as the ANSWER does, with its scale word, so the number and unit read as in the "
        + "ANSWER (\"2.642\" with \"trillion US$\", \"210\" with \"million\", \"8,515,767\" with \"km²\"). Never convert units. "
        + "In one chart or column, every value has the same unit.\n"
        + "4. If a value or cell is missing from the ANSWER, use an empty string (\"\") or leave the item out.\n"
        + "5. Keep text short (under 8 words per label). Tables: at most 3 columns. At most 6 rows or items.\n"
        + "6. Facts under EARLIER IN THIS CHAT or FROM THE SOURCES may join only when the ANSWER's visual measures the same thing.\n"
        + "7. If fewer than 2 numbers, steps or facts come from the ANSWER, reply {\"type\":\"none\"}.\n"
        + "Pick ONE type that fits:\n"
        + "- numbers to compare across things: {\"type\":\"bars\",\"title\":\"...\",\"unit\":\"...\",\"items\":[{\"label\":\"...\",\"value\":123}]}\n"
        + "- numbers that change over time, in order: {\"type\":\"line\",\"title\":\"...\",\"unit\":\"...\",\"items\":[{\"label\":\"1990\",\"value\":5}]}\n"
        + "- parts of one whole: {\"type\":\"share\",\"title\":\"...\",\"unit\":\"...\",\"items\":[{\"label\":\"...\",\"value\":40}]}\n"
        + "- a table (at most 3 columns): {\"type\":\"table\",\"title\":\"...\",\"columns\":[\"...\",\"...\",\"...\"],\"rows\":[[\"...\",\"...\",\"...\"]]}\n"
        + "- a process or how-to: {\"type\":\"steps\",\"title\":\"...\",\"steps\":[\"...\",\"...\"]}\n"
        + "- two to four options side by side: {\"type\":\"compare\",\"title\":\"...\",\"items\":[{\"name\":\"...\",\"points\":[\"...\",\"...\"]}]}\n"
        + "- key facts about one thing: {\"type\":\"facts\",\"title\":\"...\",\"facts\":[{\"label\":\"...\",\"value\":\"...\"}]}\n"
        + "\"value\" in bars, line and share is a plain number. If no visual would help, reply {\"type\":\"none\"}."

    /// The first parseable JSON object: a string-aware brace scan from each `{`.
    static func firstObject(_ s: String) -> JSONValue? {
        let u = Array(s.utf16)
        let open: UInt16 = 123, close: UInt16 = 125, quote: UInt16 = 34, backslash: UInt16 = 92
        var start = u.firstIndex(of: open)
        while let st = start {
            var depth = 0
            var inString = false
            var escaped = false
            var i = st
            while i < u.count {
                let ch = u[i]
                if inString {
                    if escaped { escaped = false } else if ch == backslash { escaped = true } else if ch == quote { inString = false }
                    i += 1
                    continue
                }
                if ch == quote {
                    inString = true
                } else if ch == open {
                    depth += 1
                } else if ch == close {
                    depth -= 1
                    if depth == 0 {
                        let text = String(decoding: u[st...i], as: UTF16.self)
                        if let v = JSONValue(jsonString: text), case .object = v { return v }
                        break
                    }
                }
                i += 1
            }
            start = u[(st + 1)...].firstIndex(of: open)
        }
        return nil
    }

    private static func cell(_ e: JSONValue) -> String { (jsonContent(e) ?? "").kotlinTrim().u16Take(maxText) }
    private static func text(_ o: JSONValue, _ k: String) -> String? { jsonContent(o[k]).map { $0.kotlinTrim().u16Take(maxText) } }
    private static func strings(_ o: JSONValue, _ k: String) -> [String] { (o[k]?.arrayValue ?? []).map(cell).filter { !$0.isEmpty } }
}

/// The visual's grounding (android `VisualCheck`): every number it shows is written in the answer (or the user's own
/// message), however it's written there, and every label shares its words with the answer. Dates count as their numbers:
/// "1913" is grounded by "12 March 1913" or "1913-03-12"; "12 March 1913" needs the 12 too.
public enum VisualCheck {
    /// The first failure, or nil when everything is grounded. Numbers are checked everywhere. Words are checked in the
    /// content (series labels, table cells, names, points, steps, fact values); headings (the title, a table's columns, a
    /// fact's name like "Height") are the model's own words for what it shows, and aren't.
    public static func check(_ v: Visual, answer: String, userText: String = "") -> (Visual.Reason, String)? {
        let source = "\(answer)\n\(userText)"
        let written = numbersIn(source)
        let words = wordsOf(source)
        func grounded(_ x: Double) -> Bool { written.contains { near($0, x) } }
        func numbersOk(_ text: String) -> String? { tokens(text).first { t in !valuesOf(t).contains(where: grounded) } }
        func labelOk(_ text: String) -> Bool { let c = contentWords(text); return c.isEmpty || c.contains { words.contains($0) } }
        var texts: [String] = []
        var labels: [String] = []
        switch v {
        case .table(let t):
            texts += t.columns
            for r in t.rows { for c in r { texts.append(c); labels.append(c) } }
        case .series(let s):
            if let bad = s.items.first(where: { !grounded($0.value) }) { return (.inventedNumbers, VisualScale.format(bad.value)) }
            for i in s.items { texts.append(i.label); labels.append(i.label) }
            // The unit is a claim too: its words come from the answer ("million", "km²"), not from the model's memory.
            if let u = s.unit {
                texts.append(u)
                if !unitOk(u, source) { return (.ungroundedLabels, u) }
            }
        case .steps(let s):
            texts += s.steps; labels += s.steps
        case .compare(let c):
            for side in c.items { texts.append(side.name); labels.append(side.name); texts += side.points; labels += side.points }
        case .facts(let f):
            for fact in f.facts { texts.append(fact.label); texts.append(fact.value); labels.append(fact.value) }
        }
        for t in texts { if let n = numbersOk(t) { return (.inventedNumbers, n) } }
        if let l = labels.first(where: { !labelOk($0) }) { return (.ungroundedLabels, l) }
        return nil
    }

    /// `visual`: what's left once everything not in the texts is out; nil when too little is left to draw (fewer than two
    /// items, rows of numbers, steps or options; no fact). `leftOut`: what came out, in order; `reason`: why the first did.
    public struct Pruned: Equatable, Sendable {
        public var visual: Visual?
        public var leftOut: [String]
        public var reason: Visual.Reason?
    }

    /// Takes out what none of the texts has (the answer, the user's message, and whatever the caller added: earlier
    /// answers, the answer's sources), instead of refusing the whole visual (adam, Nov 10):
    /// - a chart: the items with a number or a label not in the texts; a unit not in them refuses the chart;
    /// - a table: the row or the column with the most cells not in the texts or empty, again and again until every cell
    ///   is backed (the first column, the names, stays: a bad name takes its row out); a column whose heading holds a
    ///   number not in the texts goes too;
    /// - steps, a comparison's points and options, facts: the lines not in the texts.
    public static func prune(_ v: Visual, answer: String, userText: String = "") -> Pruned {
        let g = Ground("\(answer)\n\(userText)")
        var out: [String] = []
        var reason: Visual.Reason?
        func note(_ f: (String, Visual.Reason)) {
            if !out.contains(f.0) { out.append(f.0) }
            if reason == nil { reason = f.1 }
        }
        /// Why `text` isn't backed: the number not in the texts, or the text itself when its words aren't; nil when it is.
        func fault(_ text: String) -> (String, Visual.Reason)? {
            if let b = g.badNumber(text) { return (b, .inventedNumbers) }
            return g.wordsOk(text) ? nil : (text, .ungroundedLabels)
        }
        // The title and the unit are the model's words, but a number in them is a claim too (validator V-4).
        if let b = g.badNumber(v.title) { return Pruned(visual: nil, leftOut: [b], reason: .inventedNumbers) }
        let left: Visual?
        switch v {
        case .series(let s):
            if let u = s.unit {
                if let b = g.badNumber(u) { return Pruned(visual: nil, leftOut: [b], reason: .inventedNumbers) }
                if !unitOk(u, g.source) { return Pruned(visual: nil, leftOut: [u], reason: .ungroundedLabels) }
            }
            let labels = s.items.map(\.label)
            let kept = s.items.filter { item in
                let f: (String, Visual.Reason)?
                if !g.grounded(item.value) {
                    f = (VisualScale.format(item.value), .inventedNumbers)
                } else if let lf = fault(item.label) {
                    f = lf
                } else if !g.paired(item.label, item.value, labels, s.items) {
                    f = ("\(item.label) \(VisualScale.format(item.value))", .unpaired)
                } else {
                    f = nil
                }
                if let f { note(f) }
                return f == nil
            }
            if kept.count >= 2 && (s.kind != .share || VisualScale.canShare(kept.map(\.value))) {
                var copy = s
                copy.items = kept
                left = .series(copy)
            } else {
                left = nil
            }
        case .table(let t):
            left = pruneTable(t, g, note: note, fault: fault)
        case .steps(let s):
            let kept = s.steps.filter { st in
                if let f = fault(st) { note(f); return false }
                return true
            }
            left = kept.count >= 2 ? .steps(Visual.Steps(s.title, kept)) : nil
        case .compare(let c):
            let items: [CardSide] = c.items.compactMap { side in
                if let f = fault(side.name) { note(f); return nil }
                let kept = side.points.filter { p in
                    if let f = fault(p) { note(f); return false }
                    return true
                }
                return kept.isEmpty ? nil : CardSide(side.name, kept)
            }
            left = items.count >= 2 ? .compare(Visual.Compare(c.title, items)) : nil
        case .facts(let fs):
            let kept = fs.facts.filter { fact in
                let f = g.badNumber(fact.label).map { ($0, Visual.Reason.inventedNumbers) } ?? fault(fact.value)
                if let f { note(f) }
                return f == nil
            }
            left = kept.isEmpty ? nil : .facts(Visual.Facts(fs.title, kept))
        }
        return Pruned(visual: left, leftOut: out, reason: left == nil ? (reason ?? .empty) : reason)
    }

    private static func pruneTable(
        _ v: Visual.Table, _ g: Ground, note: ((String, Visual.Reason)) -> Void, fault: (String) -> (String, Visual.Reason)?
    ) -> Visual? {
        func at(_ r: [String], _ i: Int) -> String { i < r.count ? r[i] : "" }
        var cols = v.columns.indices.filter { c in
            if c == 0 { return true }
            if let b = g.badNumber(v.columns[c]) { note((b, .inventedNumbers)); return false }
            return true
        }
        // Rows by index: Android drops a row by identity, so two equal rows stay two.
        var rows = v.rows.indices.filter { i in
            let name = at(v.rows[i], 0)
            if let f = fault(name) { note(f); return false }
            return !name.allSatisfy(\.isWhitespace)
        }
        // A cell is bad when it's empty, holds something not in the texts, or a number the answer gives another row's
        // name (V-3); each round removes the worst line.
        let names = v.rows.map { at($0, 0) }
        // Every (row name, number) of the table, for which side of a number its name is written on.
        let cellItems: [VisualItem] = v.rows.flatMap { r in
            r.dropFirst().flatMap { c in tokens(c).compactMap { t in valuesOf(t).first.map { VisualItem(at(r, 0), $0) } } }
        }
        func unpaired(_ r: [String], _ cell: String) -> Bool {
            tokens(cell).contains { t in !valuesOf(t).contains { x in g.paired(at(r, 0), x, names, cellItems) } }
        }
        var badCache: [Int: Bool] = [:]
        func bad(_ ri: Int, _ c: Int) -> Bool {
            let key = ri * 64 + c
            if let b = badCache[key] { return b }
            let r = v.rows[ri]
            let cell = at(r, c)
            let b = cell.allSatisfy(\.isWhitespace) || fault(cell) != nil || unpaired(r, cell)
            badCache[key] = b
            return b
        }
        /// Why a cell that comes out came out: its own fault, or a number that belongs to another row.
        func cellFault(_ r: [String], _ cell: String) -> (String, Visual.Reason)? {
            if let f = fault(cell) { return f }
            return unpaired(r, cell) ? ("\(at(r, 0)) \(cell)", .unpaired) : nil
        }
        while true {
            let dataCols = cols.filter { $0 > 0 }
            if rows.isEmpty || dataCols.isEmpty { break }
            // Each round takes out the line that removes the most bad cells for the fewest good ones (bad − good): with
            // Brazil backed and Russia invented, Russia's row goes, then the columns Brazil has no value for.
            func score(_ b: Int, _ total: Int) -> Int { b - (total - b) }
            func firstMax(_ xs: [(Int, Int)], _ total: Int) -> (Int, Int) {
                var best = xs[0]
                for x in xs.dropFirst() where score(x.1, total) > score(best.1, total) { best = x }
                return best
            }
            let worstRow = firstMax(rows.map { ri in (ri, dataCols.count { bad(ri, $0) }) }, dataCols.count)
            let worstCol = firstMax(dataCols.map { c in (c, rows.count { bad($0, c) }) }, rows.count)
            if worstRow.1 == 0 && worstCol.1 == 0 { break }
            let rowScore = worstRow.1 == 0 ? Int.min : score(worstRow.1, dataCols.count)
            let colScore = worstCol.1 == 0 ? Int.min : score(worstCol.1, rows.count)
            // On a tie, a column goes: the rows are the things compared.
            if colScore >= rowScore {
                for ri in rows {
                    let cell = at(v.rows[ri], worstCol.0)
                    if !cell.allSatisfy(\.isWhitespace), let f = cellFault(v.rows[ri], cell) { note(f) }
                }
                cols.removeAll { $0 == worstCol.0 }
            } else {
                for c in dataCols {
                    let cell = at(v.rows[worstRow.0], c)
                    if !cell.allSatisfy(\.isWhitespace), let f = cellFault(v.rows[worstRow.0], cell) { note(f) }
                }
                rows.removeAll { $0 == worstRow.0 }
            }
        }
        let dataCols = cols.filter { $0 > 0 }
        let cells = rows.reduce(0) { sum, ri in sum + dataCols.count { !bad(ri, $0) } }
        guard !rows.isEmpty, !dataCols.isEmpty, cells >= 2 else { return nil }
        return .table(Visual.Table(v.title, cols.map { v.columns[$0] }, rows.map { ri in cols.map { at(v.rows[ri], $0) } }))
    }

    static func near(_ a: Double, _ x: Double) -> Bool { abs(a - x) <= 1e-9 * max(1.0, abs(x)) }

    /// The texts a visual is checked against, read once.
    final class Ground {
        let source: String
        private let written: Set<Double>
        private let words: Set<String>
        /// Where each number is written in the source (its start), by value.
        private let at: [(Int, [Double])]
        private let foldedSource: String
        private let sentenceEnds: [Int]
        private var placesCache: [String: [Int]] = [:]
        private var amongCache: [String: [Int]] = [:]
        private var orderCache: [[VisualItem]: Bool] = [:]

        init(_ source: String) {
            self.source = source
            written = numbersIn(source)
            words = wordsOf(source)
            at = token.matches(in: source).map { m in (m.range.location, valuesOf((source as NSString).substring(with: m.range).kotlinTrim())) }
            foldedSource = fold(source)
            sentenceEnds = [0] + sentenceEnd.matches(in: source).map { $0.range.location + $0.range.length } + [source.u16]
        }

        func grounded(_ x: Double) -> Bool { written.contains { near($0, x) } }

        /// Where `label`'s words (2 characters or more, letters or digits: "K2" too) are written in the source.
        private func placesOf(_ label: String) -> [Int] {
            if let p = placesCache[label] { return p }
            let f = fold(label)
            let ws = wordRx.matches(in: f).map { (f as NSString).substring(with: $0.range) }
                .filter { w in !stop.contains(w) && w.contains(where: \.isLetter) }
            let p = ws.flatMap { w -> [Int] in
                // A word with a digit ends there: "Part1" isn't "Part10" (validator V-3).
                let end = w.unicodeScalars.contains(where: isDigit) ? "(?![\\p{N}])" : ""
                return Rx("(?<![\\p{L}\\p{N}])" + regexLiteral(stem(w)) + end).matches(in: foldedSource).map(\.range.location)
            }
            placesCache[label] = p
            return p
        }

        /// `label`'s places, without those inside a longer label of the same visual that contains it: "Sudan" isn't where
        /// "South Sudan" is written (validator V-3).
        private func placesAmong(_ label: String, _ labels: [String]) -> [Int] {
            let key = label + "\u{0}" + labels.joined(separator: "\u{0}")
            if let p = amongCache[key] { return p }
            let own = fold(label).kotlinTrim()
            let ownRx = Rx("(?<![\\p{L}\\p{N}])" + regexLiteral(own) + "(?![\\p{L}\\p{N}])")
            let covered: [NSRange] = labels.map { fold($0).kotlinTrim() }
                .filter { $0 != own && $0.u16 > own.u16 && ownRx.containsMatch(in: $0) }
                .flatMap { longer in Rx(regexLiteral(longer)).matches(in: foldedSource).map(\.range) }
            let p = placesOf(label).filter { p in !covered.contains { p >= $0.location && p < $0.location + $0.length } }
            amongCache[key] = p
            return p
        }

        /// The value `x` stands next to `label` in the source, not next to another of the visual's `labels` (validator
        /// V-3: "Paris 2.1 million, Lyon 0.5 million" drawn swapped passed): for some place `x` is written, the nearest
        /// label (one before it counts at half the distance of one after) is `label`. True when no label is near any
        /// place `x` is written, so a number the answer gives without naming its item isn't refused for that.
        func paired(_ label: String, _ x: Double, _ labels: [String], _ items: [VisualItem] = []) -> Bool {
            // Which side of its number a name is written on, read from this answer and this visual (validator V-3): the
            // reading under which more of the visual's items stand by their own name. The answer's own sentences decide
            // first (validator Q-A3).
            var numbersFirst = false
            if items.count >= 2 {
                if let w = writtenNumbersFirst(labels) {
                    numbersFirst = w
                } else if let c = orderCache[items] {
                    numbersFirst = c
                } else {
                    let c = items.count { pairedAs($0.label, $0.value, labels, true) } > items.count { pairedAs($0.label, $0.value, labels, false) }
                    orderCache[items] = c
                    numbersFirst = c
                }
            }
            return pairedAs(label, x, labels, numbersFirst)
        }

        /// Which side of their numbers the answer writes these `labels` on, from its sentences alone: a label with numbers
        /// before it in its sentence and none after votes numbers-first, the opposite votes names-first. Nil on a tie.
        private func writtenNumbersFirst(_ labels: [String]) -> Bool? {
            let ends = sentenceEnds
            var first = 0, after = 0
            for l in distinct(labels) {
                for w in placesAmong(l, labels) {
                    let i = max(0, ends.lastIndex { $0 <= w } ?? -1)
                    let from = ends[i]
                    let to = i + 1 < ends.count ? ends[i + 1] : source.u16
                    let before = at.contains { $0.0 >= from && $0.0 < w }
                    let later = at.contains { $0.0 >= w + l.u16 && $0.0 < to }
                    if before && !later { first += 1 } else if later && !before { after += 1 }
                }
            }
            return first == after ? nil : first > after
        }

        /// `numbersFirst` false: the name before the number counts, at half the distance of one after (the original
        /// rule). True: the name after the number counts, at half the distance of one before.
        private func pairedAs(_ label: String, _ x: Double, _ labels: [String], _ numbersFirst: Bool) -> Bool {
            let nearDistance = 400
            let places = at.filter { $0.1.contains { near($0, x) } }.map(\.0)
            if places.isEmpty { return false }
            let byLabel = distinct(labels).map { ($0, placesAmong($0, labels)) }
            var anyNear = false
            for p in places {
                // A sentence (or line) that names exactly one of the labels: its number is that label's, whichever side
                // it's written on (CodeRabbit on all73). Distance decides only otherwise.
                let here = byLabel.filter { $0.1.contains { w in sameSentence(w, p) } }
                if here.count == 1 {
                    anyNear = true
                    if here[0].0 == label { return true }
                    continue
                }
                func dist(_ w: Int) -> Int {
                    numbersFirst ? (w >= p ? (w - p) / 2 : p - w) : (w <= p ? (p - w) / 2 : w - p)
                }
                func nearestOf(_ keep: (Int) -> Bool) -> [(String, Int)] {
                    byLabel.map { l, ws in (l, ws.filter(keep).map(dist).min() ?? Int.max) }.filter { $0.1 <= nearDistance }
                }
                // The next sentence's subject doesn't take this number, but only while another name stays near (R-B1).
                var field = nearestOf { w in !self.acrossSentence(w, p, numbersFirst) }
                if field.isEmpty { field = nearestOf { _ in true } }
                guard var nearest = field.first else { continue }
                for c in field.dropFirst() where c.1 < nearest.1 { nearest = c }
                anyNear = true
                if nearest.0 == label { return true }
            }
            return !anyNear
        }

        private func between(_ w: Int, _ p: Int) -> String {
            let len = source.u16
            let from = min(min(w, p), len)
            return source.u16Substring(from, max(from, min(len, max(w, p) + 1)))
        }

        /// No sentence end or line break between `w` and `p` (looking one character past the later one).
        private func sameSentence(_ w: Int, _ p: Int) -> Bool {
            let b = between(w, p)
            return !sentenceEnd.containsMatch(in: b) && !b.contains("\n")
        }

        /// A name on the far side of its number (after it when names come first) and past a sentence's end is the next
        /// sentence's subject, not this number's: "…com uma área de 8.515.814 km². A Índia é…" is Brasil's area.
        private func acrossSentence(_ w: Int, _ p: Int, _ numbersFirst: Bool) -> Bool {
            let far = numbersFirst ? w < p : w > p
            if !far { return false }
            // One character past the span, so a sentence that starts with the number itself ends the one before it (Q-A3).
            let b = between(w, p)
            // A clause break on the far side too: "…in Paris, 0.5 million in Lyon" is Lyon's 0.5 (Q-A3).
            return sentenceEnd.containsMatch(in: b) || clauseEnd.containsMatch(in: b)
        }

        func badNumber(_ text: String) -> String? { tokens(text).first { t in !valuesOf(t).contains(where: grounded) } }
        func wordsOk(_ text: String) -> Bool { let c = contentWords(text); return c.isEmpty || c.contains { words.contains($0) } }
    }

    /// A unit the answer uses: each of its words (3 letters or more: "million", "trillion", "milhões") is in the answer,
    /// and each symbol or short unit (km², %, US$, °C, m) appears in it as written.
    public static func unitOk(_ unit: String, _ source: String) -> Bool {
        let src = fold(source)
        let have = Set(contentWords(source))
        let fu = fold(unit)
        let ws = letters3.matches(in: fu).map { (fu as NSString).substring(with: $0.range) }.filter { !stop.contains($0) }
        if ws.contains(where: { !have.contains(stem($0)) }) { return false }
        let symbols = symbolRx.matches(in: fu).map { (fu as NSString).substring(with: $0.range).kotlinTrim() }.filter { !$0.isEmpty }
        return symbols.allSatisfy { src.contains($0) }
    }

    /// A number as written: thousands in groups of three ("1,234", "1.234", "1 234") or plain digits, a decimal part, a
    /// minus only where it can't be a dash ("1913-03-12" is 1913, 3 and 12), and a word for thousands or more. A list
    /// ("1913, 1914") stays two numbers.
    static let token = Rx.java(
        #"(?<![\p{N}.,])(?:(?<![\p{L}\p{N}])[-−])?(?:\d{1,3}(?:[.,  ]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)?)"#
            + #"(?:\s*(?:%|million|millions|billion|billions|thousand|trillion|mil|milhão|milhões|bilhão|bilhões|bi|mi|k)(?![\p{L}]))?"#,
        ignoreCase: true
    )
    private static let clauseEnd = Rx.java(#"[,;]\s|\s(?:and|e|y)\s"#, ignoreCase: true)
    private static let sentenceEnd = Rx.java(#"[.!?](?:\s*\[\d{1,3}\])?\s+(?=\p{Lu}|\d)"#)
    private static let wordRx = Rx(#"[\p{L}\p{N}]{2,}"#)
    private static let letters3 = Rx(#"\p{L}{3,}"#)
    private static let symbolRx = Rx.java(#"[^\p{L}\p{N}\s()/.,-]+|(?<!\p{L})\p{L}{1,2}[²³]?(?!\p{L})"#)
    private static let trailingWord = Rx(#"[\p{L}%]+$"#)
    private static let threeDigits = Rx.javaWhole(#"^\d{1,3}[.,]\d{3}$"#)
    private static let marksRx = Rx(#"\p{M}+"#)

    /// `text` with each number written as `source` writes the same value ("3,287,263" in a card under a Portuguese answer
    /// that wrote "3.287.263"); a number `source` doesn't hold, or holds in two spellings, stays as it is.
    public static func asWritten(_ text: String, _ source: String) -> String {
        if source.allSatisfy(\.isWhitespace) { return text }
        var spelled: [Double: Set<String>] = [:]
        for t in tokens(source) {
            let vs = valuesOf(t)
            if vs.count == 1 { spelled[vs[0], default: []].insert(t) }
        }
        return token.replace(text) { m in
            let whole = (text as NSString).substring(with: m.range)
            let t = whole.kotlinTrim()
            var picks: [String] = []
            for v in valuesOf(t) {
                if let set = spelled[v], set.count == 1, let one = set.first, !picks.contains(one) { picks.append(one) }
            }
            guard picks.count == 1, picks[0] != t else { return whole }
            return whole.replacingOccurrences(of: t, with: picks[0])
        }
    }

    static func tokens(_ text: String) -> [String] {
        token.matches(in: text).map { (text as NSString).substring(with: $0.range).kotlinTrim() }
    }

    /// Every number in `text`, each in every way it could be read (EN and PT separators, with and without its multiplier word).
    public static func numbersIn(_ text: String) -> Set<Double> { Set(tokens(text).flatMap(valuesOf)) }

    /// The values one written number can mean: "1,234" is 1234 (or 1.234 in PT); "1.234" is 1.234 (or 1234 in PT);
    /// "3,5" is 3.5; "1 234" is 1234; "12%" is 12; "1.5 million" and "1,5 milhão" are 1.5 and 1,500,000.
    public static func valuesOf(_ token: String) -> [Double] {
        let t = token.kotlinTrim().replacingOccurrences(of: "−", with: "-")
        let wm = trailingWord.firstMatch(in: t)
        let wordRaw = wm.map { (t as NSString).substring(with: $0.range) }
        let digits = (wordRaw.map { String(t.dropLast($0.count)) } ?? t).kotlinTrim()
        let reads = readings(digits.replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: "\u{202f}", with: "")
            .replacingOccurrences(of: " ", with: ""))
        let mult: Double? = switch wordRaw?.lowercased() {
        case "thousand", "mil", "k": 1e3
        case "million", "millions", "milhão", "milhões", "mi": 1e6
        case "billion", "billions", "bilhão", "bilhões", "bi": 1e9
        case "trillion": 1e12
        default: nil
        }
        if let mult { return reads + reads.map { $0 * mult } }
        return reads
    }

    /// How a number is read from the way it's written, one reading where the form says which (validator V-2): both
    /// separators, the last one is the decimal; several of one, thousands; one comma before exactly three digits
    /// ("1,234"), thousands, else a decimal ("3,5"); one dot before anything but exactly three digits, a decimal. Only one
    /// dot before exactly three digits ("1.234": EN 1.234, PT 1234) keeps both readings.
    public static func readings(_ n: String) -> [Double] {
        let neg = n.hasPrefix("-")
        let d = neg ? String(n.dropFirst()) : n
        let commas = d.count { $0 == "," }
        let dots = d.count { $0 == "." }
        func num(_ x: String) -> Double? { kotlinDouble(x).map { neg ? -$0 : $0 } }
        let three = threeDigits.containsMatch(in: d)
        let one: Double?
        if commas > 0 && dots > 0 {
            let lastComma = (d as NSString).range(of: ",", options: .backwards).location
            let lastDot = (d as NSString).range(of: ".", options: .backwards).location
            one = lastComma > lastDot
                ? num(d.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
                : num(d.replacingOccurrences(of: ",", with: ""))
        } else if commas > 1 {
            one = num(d.replacingOccurrences(of: ",", with: ""))
        } else if dots > 1 {
            one = num(d.replacingOccurrences(of: ".", with: ""))
        } else if commas == 1 {
            one = three ? num(d.replacingOccurrences(of: ",", with: "")) : num(d.replacingOccurrences(of: ",", with: "."))
        } else if dots == 1 && three {
            return [num(d), num(d.replacingOccurrences(of: ".", with: ""))].compactMap { $0 }
        } else {
            one = num(d)
        }
        return one.map { [$0] } ?? []
    }

    /// Kotlin `toDoubleOrNull` for what a number token can hold: digits, a dot, an exponent.
    private static func kotlinDouble(_ s: String) -> Double? {
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || $0 == "." || $0 == "e" || $0 == "E" || $0 == "-" || $0 == "+" })
        else { return nil }
        return Double(s)
    }

    static let stop: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "are", "was", "were", "has", "have", "its", "into", "than", "per", "about",
        "de", "da", "do", "das", "dos", "em", "para", "com", "por", "que", "uma", "um", "os", "as", "na", "no", "nas", "nos", "mais", "como",
    ]

    static func fold(_ s: String) -> String { marksRx.replace(s.lowercased().decomposedStringWithCanonicalMapping, with: "") }

    /// A word reduced to a rough stem, so "volcanoes" meets "volcano" and "eruptions" "eruption".
    static func stem(_ w: String) -> String {
        let n = w.u16
        if n > 4 && w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if n > 4 && w.hasSuffix("oes") { return String(w.dropLast(2)) }
        if n > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast(1)) }
        return w
    }

    static func contentWords(_ text: String) -> [String] {
        let f = fold(text)
        return letters3.matches(in: f).map { (f as NSString).substring(with: $0.range) }.filter { !stop.contains($0) }.map(stem)
    }

    private static func wordsOf(_ text: String) -> Set<String> { Set(contentWords(text)) }

    private static func isDigit(_ u: Unicode.Scalar) -> Bool { u.properties.generalCategory == .decimalNumber }

    private static func distinct(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }
}

/// What the app computes for a visual (android `VisualScale`): shares that add up, axes, which views the same data
/// allows, and a text copy.
public enum VisualScale {
    /// Parts that can make a whole: at least two, none negative, the total above zero, at most `Visual.maxShareParts`.
    public static func canShare(_ values: [Double]) -> Bool {
        (2...Visual.maxShareParts).contains(values.count) && values.allSatisfy { $0 >= 0 && $0.isFinite } && values.reduce(0, +) > 0
    }

    /// Each part's whole percent, adding up to exactly 100 (largest remainder): 1/3 each is 34, 33, 33.
    public static func percents(_ values: [Double]) -> [Int] {
        let total = values.reduce(0, +)
        if total <= 0 { return values.map { _ in 0 } }
        let raw = values.map { $0 * 100.0 / total }
        var floors = raw.map { Int($0.rounded(.down)) }
        var left = 100 - floors.reduce(0, +)
        let order = raw.indices.sorted { a, b in
            let ra = raw[a] - Double(floors[a]), rb = raw[b] - Double(floors[b])
            return ra != rb ? ra > rb : a < b
        }
        for i in order where left > 0 {
            floors[i] += 1
            left -= 1
        }
        return floors
    }

    /// An axis: ticks at a round step (1, 2, 2.5 or 5 times a power of ten), from zero for bars, around the data for a line.
    public struct Axis: Equatable, Sendable {
        public var min: Double
        public var max: Double
        public var step: Double
        public var ticks: [Double] {
            var out: [Double] = []
            var v = min
            while v <= max + step * 1e-9 { out.append(v); v += step }
            return out
        }
    }

    public static func axis(_ values: [Double], fromZero: Bool, ticks: Int = 4) -> Axis {
        var lo = values.min() ?? 0.0
        var hi = values.max() ?? 1.0
        if fromZero { lo = Swift.min(0.0, lo); hi = Swift.max(0.0, hi) }
        if hi == lo {
            hi = lo + 1
            if !fromZero { lo -= 1 }
        }
        let step = niceStep((hi - lo) / Double(ticks))
        return Axis(min: (lo / step).rounded(.down) * step, max: (hi / step).rounded(.up) * step, step: step)
    }

    private static func niceStep(_ raw: Double) -> Double {
        let p = pow(10.0, log10(raw).rounded(.down))
        let f = raw / p
        let m: Double = f <= 1 ? 1.0 : f <= 2 ? 2.0 : f <= 2.5 ? 2.5 : f <= 5 ? 5.0 : 10.0
        return p * m
    }

    /// The views a series can switch to with no new model call: bars and a table always, a line from 3 points, and a
    /// pie only when the model said the numbers are parts of one whole (validator V-6: a pie of unrelated heights).
    public static func kinds(_ s: Visual.Series) -> [String] {
        var out = ["bars"]
        if s.items.count >= 3 { out.append("line") }
        if s.kind == .share && canShare(s.items.map(\.value)) { out.append("share") }
        out.append("table")
        return out
    }

    /// The same series as another kind (bars, line, share); a share only when the parts can make a whole.
    public static func asKind(_ s: Visual.Series, _ kind: Visual.SeriesKind) -> Visual.Series? {
        if kind == .share && !canShare(s.items.map(\.value)) { return nil }
        var copy = s
        copy.kind = kind
        return copy
    }

    /// A series as a two-column table: the label, then the value with its unit.
    public static func asTable(_ s: Visual.Series) -> Visual.Table {
        Visual.Table(s.title, ["", s.unit ?? ""], s.items.map { [$0.label, format($0.value)] })
    }

    /// 1500.0 → "1500", 3.25 → "3.25": no trailing zeros, no exponent (Kotlin: `BigDecimal(v).round(10 digits)
    /// .stripTrailingZeros().toPlainString()`).
    public static func format(_ v: Double) -> String {
        if !v.isFinite { return "\(v)" }
        if v == v.rounded(.down) && abs(v) < 1e15 { return String(Int64(v)) }
        // Ten significant digits, then written out without an exponent.
        let e = String(format: "%.9e", v)
        guard let ePos = e.firstIndex(where: { $0 == "e" }), let exp = Int(e[e.index(after: ePos)...]) else { return "\(v)" }
        var mantissa = String(e[..<ePos])
        let negative = mantissa.hasPrefix("-")
        if negative { mantissa.removeFirst() }
        let digits = Array(mantissa.replacingOccurrences(of: ".", with: ""))
        var intPart: String
        var frac: String
        if exp >= digits.count - 1 {
            intPart = String(digits) + String(repeating: "0", count: exp - (digits.count - 1))
            frac = ""
        } else if exp >= 0 {
            intPart = String(digits[0...exp])
            frac = String(digits[(exp + 1)...])
        } else {
            intPart = "0"
            frac = String(repeating: "0", count: -exp - 1) + String(digits)
        }
        while frac.hasSuffix("0") { frac.removeLast() }
        if intPart.isEmpty { intPart = "0" }
        return (negative ? "-" : "") + intPart + (frac.isEmpty ? "" : "." + frac)
    }

    /// The visual as Markdown, for Copy: a table, "label: value unit" lines, numbered steps, or name: value lines.
    public static func markdown(_ v: Visual) -> String {
        var s = ""
        if !v.title.allSatisfy(\.isWhitespace) { s += "**\(v.title)**\n\n" }
        switch v {
        case .table(let t):
            s += "| " + t.columns.joined(separator: " | ") + " |\n"
            s += "|" + t.columns.map { _ in " --- " }.joined(separator: "|") + "|\n"
            for r in t.rows { s += "| " + r.joined(separator: " | ") + " |\n" }
        case .series(let se):
            let pct = se.kind == .share ? percents(se.items.map(\.value)) : nil
            for (i, item) in se.items.enumerated() {
                s += "- \(item.label): \(format(item.value))"
                if let u = se.unit { s += " \(u)" }
                if let pct { s += " (\(pct[i])%)" }
                s += "\n"
            }
        case .steps(let st):
            for (i, step) in st.steps.enumerated() { s += "\(i + 1). \(step)\n" }
        case .compare(let c):
            for side in c.items {
                s += "**\(side.name)**\n"
                for p in side.points { s += "- \(p)\n" }
            }
        case .facts(let f):
            for fact in f.facts { s += "- \(fact.label): \(fact.value)\n" }
        }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return s
    }
}

/// A JSON primitive's content as kotlinx's `contentOrNull` gives it; nil for null, arrays and objects.
func jsonContent(_ v: JSONValue?) -> String? {
    switch v {
    case .string(let s)?: s
    case .int(let n)?: "\(n)"
    case .double(let d)?: VisualScale.format(d)
    case .bool(let b)?: b ? "true" : "false"
    default: nil
    }
}
