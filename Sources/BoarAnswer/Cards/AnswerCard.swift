import BoarCore
import BoarRAG
import Foundation

/// The card shown under one answer (android `AnswerCard`; Cards, adam's interview, Nov 14; t9 0207 items 3 and 4): what
/// was drawn, in which shape, from the rules (`CardRules`) or from the model (`Visual`, "made by the model · checked
/// against the answer"). Pure data, kept in the answer's own message meta ("card", with the checklist's ticks beside it
/// in "cardTicks", adam: "ticks kept with the chat").
public struct AnswerCard: Equatable, Sendable {
    public typealias Shape = CardRules.Shape

    public var shape: Shape
    public var title: String
    public var body: Body
    /// Made by the model (the "slower" row), checked against the answer; false: found by the rules in the answer's text.
    public var byModel: Bool
    /// What the model's card had that no text holds, taken out (Visual's "left out" line).
    public var leftOut: [String]
    /// The checklist's ticked steps, by index (only for `.steps`).
    public var ticks: Set<Int>

    public init(_ shape: Shape, _ title: String, _ body: Body, byModel: Bool = false, leftOut: [String] = [], ticks: Set<Int> = []) {
        self.shape = shape; self.title = title; self.body = body; self.byModel = byModel; self.leftOut = leftOut; self.ticks = ticks
    }

    public enum Body: Equatable, Sendable {
        /// Labelled numbers of one unit: bars, a table, a pie or a line. Each point's `written` as the answer writes it.
        case series(unit: String, points: [CardRules.Point])
        case table(header: [String], rows: [[String]])
        case steps([String])
        case facts([CardFact])
        case compare([CardSide])
    }

    /// One pill of the card's switch: the `card`-th card the rules found, in `shape`.
    public struct Choice: Equatable, Hashable, Sendable {
        public var card: Int
        public var shape: Shape
        public init(_ card: Int, _ shape: Shape) { self.card = card; self.shape = shape }
    }

    /// What the rules found, for the plugins sheet's second line ("A chart of 3 numbers"); the app words it.
    public enum Found: Sendable, Equatable { case chart, table, steps, facts, compare }

    /// The one switch under the card (adam, Nov 14: "the best one, with a switch to the other shapes that fit"): every
    /// shape of every card the rules found, best card first.
    public static func choices(_ cards: [CardRules.Card]) -> [Choice] {
        cards.enumerated().flatMap { i, c in c.shapes.map { Choice(i, $0) } }
    }

    /// `card` in `shape` (a shape it doesn't have falls back to its first).
    public static func of(_ card: CardRules.Card, _ shape: Shape, title: String) -> AnswerCard {
        let s = card.shapes.contains(shape) ? shape : card.shapes[0]
        let body: Body = switch card {
        case .chart(let points, let unit, _): .series(unit: unit, points: points)
        case .table(let header, let rows): .table(header: header, rows: rows)
        case .steps(let items): .steps(items)
        case .facts(let pairs): .facts(pairs)
        case .compare(let sides): .compare(sides)
        }
        return AnswerCard(s, title, body)
    }

    /// Which kind a card is and how many items it holds, for the sheet's line.
    public static func found(_ card: CardRules.Card) -> (Found, Int) {
        switch card {
        case .chart(let points, _, _): (.chart, points.count)
        case .table(_, let rows): (.table, rows.count)
        case .steps(let items): (.steps, items.count)
        case .facts(let pairs): (.facts, pairs.count)
        case .compare(let sides): (.compare, sides.count)
        }
    }

    /// A rule card's title: the things compared ("Solar · Wind"), else the answer's first source, else the question,
    /// short. The rules never invent a title, so it comes from what the chat already shows.
    public static func titleFor(_ card: CardRules.Card, question: String, sources: [String]) -> String {
        if case .compare(let sides) = card { return sides.map(\.name).joined(separator: " · ") }
        if let s = sources.first(where: { !$0.allSatisfy(\.isWhitespace) }) { return s.kotlinTrim().u16Take(80) }
        let q = question.kotlinTrim().kotlinTrimEnd(["?", ".", "!"]).kotlinTrim()
        if q.u16 <= 60 { return q }
        var cut = q.u16Take(57)
        while let l = cut.last, l.isWhitespace { cut.removeLast() }
        return cut + "…"
    }

    /// The model's visual (Visual.parse, already checked against the answer) as a card. Its numbers are written as the
    /// `answer` writes them: a Portuguese answer's "3.287.263" stays 3.287.263 on the card.
    public static func ofVisual(_ v: Visual, leftOut: [String], fallbackTitle: String, answer: String = "") -> AnswerCard {
        // The answer's [n] marks don't belong on the card: Press renumbers the answer, not the card (validator R-E2).
        func c(_ s: String) -> String { CiteMarks.strip(s).kotlinTrim() }
        func w(_ s: String) -> String { VisualCheck.asWritten(c(s), answer) }
        let t = c(v.title)
        let title = t.allSatisfy(\.isWhitespace) ? fallbackTitle : t
        switch v {
        case .series(let s):
            // A negative value as a bar or a line is drawn by its length: the coldest place would look the hottest. A
            // table keeps the sign (validator R-E1, as B-9 did for the rules' charts).
            let shape: Shape =
                if s.items.contains(where: { $0.value < 0 }) && s.kind != .share { .table }
                else if s.kind == .bars { .bars }
                else if s.kind == .line { .line }
                else { .pie }
            let unit = c(s.unit ?? "")
            let points = s.items.map { CardRules.Point(c($0.label), (w(VisualScale.format($0.value)) + " " + unit).kotlinTrim(), $0.value) }
            return AnswerCard(shape, title, .series(unit: unit, points: points), byModel: true, leftOut: leftOut)
        case .table(let tb):
            return AnswerCard(.table, title, .table(header: tb.columns.map(c), rows: tb.rows.map { $0.map(w) }), byModel: true, leftOut: leftOut)
        case .steps(let st):
            return AnswerCard(.checklist, title, .steps(st.steps.map(c)), byModel: true, leftOut: leftOut)
        case .facts(let f):
            return AnswerCard(.facts, title, .facts(f.facts.map { CardFact(c($0.label), w($0.value)) }), byModel: true, leftOut: leftOut)
        case .compare(let cp):
            return AnswerCard(.compare, title, .compare(cp.items.map { CardSide(c($0.name), $0.points.map(c)) }), byModel: true, leftOut: leftOut)
        }
    }

    /// A pie's parts as whole percents adding up to 100 (VisualScale.percents).
    public static func percents(_ points: [CardRules.Point]) -> [Int] { VisualScale.percents(points.map(\.value)) }

    /// The card as a table, for a pie or a line printed and for the Markdown: header and rows. A series has two columns,
    /// its label and its value as written.
    public static func asTable(_ card: AnswerCard, nameLabel: String = "", valueLabel: String = "") -> (header: [String], rows: [[String]])? {
        switch card.body {
        case .series(let unit, let points):
            ([nameLabel, valueLabel.allSatisfy(\.isWhitespace) ? unit : valueLabel], points.map { [$0.label, $0.written] })
        case .table(let header, let rows): (header, rows)
        default: nil
        }
    }

    /// The card in Markdown (t9 0207 item 4): a table for a series or a table, a numbered list for steps, "- Label: value"
    /// lines for facts, a short list under each name for a comparison. Its title first, bold.
    public static func markdown(_ card: AnswerCard, nameLabel: String = "", valueLabel: String = "") -> String {
        var s = ""
        if !card.title.allSatisfy(\.isWhitespace) { s += "**\(cell(card.title))**\n\n" }
        switch card.body {
        case .series, .table:
            let (header, rows) = asTable(card, nameLabel: nameLabel, valueLabel: valueLabel)!
            let n = max(header.count, rows.map(\.count).max() ?? 0)
            func row(_ r: [String]) -> String {
                "| " + (r + Array(repeating: "", count: max(0, n - r.count))).map(cell).joined(separator: " | ") + " |"
            }
            s += row(header) + "\n"
            s += "|" + (0..<n).map { _ in " --- " }.joined(separator: "|") + "|\n"
            for r in rows { s += row(r) + "\n" }
        case .steps(let items):
            for (i, it) in items.enumerated() { s += "\(i + 1). \(it.kotlinTrim())\n" }
        case .facts(let pairs):
            for p in pairs { s += "- \(p.label.kotlinTrim()): \(p.value.kotlinTrim())\n" }
        case .compare(let sides):
            for side in sides {
                s += "**\(side.name.kotlinTrim())**\n"
                for p in side.points { s += "- \(p.kotlinTrim())\n" }
            }
        }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return s
    }

    private static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|").kotlinTrim()
    }

    // MARK: JSON

    public static func toJson(_ card: AnswerCard, withTicks: Bool = false) -> JSONValue {
        var m: [String: JSONValue] = ["shape": .string(card.shape.rawValue), "title": .string(card.title), "byModel": .bool(card.byModel)]
        if !card.leftOut.isEmpty { m["leftOut"] = .array(card.leftOut.map { .string($0) }) }
        switch card.body {
        case .series(let unit, let points):
            m["kind"] = .string("series")
            m["unit"] = .string(unit)
            m["points"] = .array(points.map { .object(["label": .string($0.label), "written": .string($0.written), "value": .double($0.value)]) })
        case .table(let header, let rows):
            m["kind"] = .string("table")
            m["header"] = .array(header.map { .string($0) })
            m["rows"] = .array(rows.map { r in .array(r.map { .string($0) }) })
        case .steps(let items):
            m["kind"] = .string("steps")
            m["steps"] = .array(items.map { .string($0) })
        case .facts(let pairs):
            m["kind"] = .string("facts")
            m["facts"] = .array(pairs.map { .object(["label": .string($0.label), "value": .string($0.value)]) })
        case .compare(let sides):
            m["kind"] = .string("compare")
            m["sides"] = .array(sides.map { .object(["name": .string($0.name), "points": .array($0.points.map { .string($0) })]) })
        }
        if withTicks && !card.ticks.isEmpty { m["ticks"] = .array(card.ticks.sorted().map { .int(Int64($0)) }) }
        return .object(m)
    }

    /// A card written by `toJson`; nil for anything else (a newer or damaged one is simply not drawn).
    public static func fromJson(_ e: JSONValue?) -> AnswerCard? {
        guard let o = e, case .object = o, let shapeName = o["shape"]?.stringValue, let shape = Shape(rawValue: shapeName) else { return nil }
        func strings(_ k: String) -> [String] { (o[k]?.arrayValue ?? []).compactMap(jsonContent) }
        func arr(_ k: String) -> [JSONValue] { o[k]?.arrayValue ?? [] }
        let body: Body
        switch o["kind"]?.stringValue {
        case "series":
            let points = arr("points").compactMap { p -> CardRules.Point? in
                guard case .object = p, let label = p["label"]?.stringValue, let value = number(p["value"]) else { return nil }
                return CardRules.Point(label, p["written"]?.stringValue ?? "", value)
            }
            if points.isEmpty { return nil }
            body = .series(unit: o["unit"]?.stringValue ?? "", points: points)
        case "table":
            body = .table(header: strings("header"), rows: arr("rows").compactMap { r in r.arrayValue?.map { jsonContent($0) ?? "" } })
        case "steps":
            let steps = strings("steps")
            if steps.isEmpty { return nil }
            body = .steps(steps)
        case "facts":
            body = .facts(arr("facts").compactMap { f in
                guard case .object = f, let l = f["label"]?.stringValue else { return nil }
                return CardFact(l, f["value"]?.stringValue ?? "")
            })
        case "compare":
            body = .compare(arr("sides").compactMap { f in
                guard case .object = f, let n = f["name"]?.stringValue else { return nil }
                return CardSide(n, (f["points"]?.arrayValue ?? []).compactMap(jsonContent))
            })
        default:
            return nil
        }
        let byModel: Bool = if case .bool(let b)? = o["byModel"] { b } else { o["byModel"]?.boolValue ?? false }
        return AnswerCard(shape, o["title"]?.stringValue ?? "", body, byModel: byModel, leftOut: strings("leftOut"), ticks: ticksOf(o["ticks"]))
    }

    /// Kotlin `doubleOrNull` on a primitive: a number, or a string that reads as one.
    private static func number(_ v: JSONValue?) -> Double? {
        switch v {
        case .int(let n)?: Double(n)
        case .double(let d)?: d
        case .string(let s)?: Double(s)
        default: nil
        }
    }

    private static func ticksOf(_ e: JSONValue?) -> Set<Int> {
        Set((e?.arrayValue ?? []).compactMap { v -> Int? in
            switch v {
            case .int, .double, .string: v.intValue
            default: nil
            }
        }.filter { $0 >= 0 })
    }

    // MARK: The message's meta

    public static let metaCard = "card"
    public static let metaTicks = "cardTicks"

    private static func metaObject(_ meta: String?) -> [String: JSONValue]? {
        guard let meta, !meta.allSatisfy(\.isWhitespace) else { return [:] }
        return JSONValue(jsonString: meta)?.objectValue
    }

    /// The card kept with an answer, with its ticks; nil when none is shown.
    public static func fromMeta(_ meta: String?) -> AnswerCard? {
        guard let o = metaObject(meta), var card = fromJson(o[metaCard]) else { return nil }
        card.ticks = ticksOf(o[metaTicks])
        return card
    }

    /// The ticks kept with an answer, shown card or not (switching to the amounts and back keeps them).
    public static func ticksFromMeta(_ meta: String?) -> Set<Int> { metaObject(meta).map { ticksOf($0[metaTicks]) } ?? [] }

    /// `meta` with `card` shown, every other key (sources, receipt, staged…) kept as it is; a nil `card` removes it and
    /// its ticks (✕). Nil when `meta` can't be read: then nothing is written over it.
    public static func withCard(_ meta: String?, _ card: AnswerCard?) -> String? {
        guard var m = metaObject(meta) else { return nil }
        if let card { m[metaCard] = toJson(card) } else { m[metaCard] = nil; m[metaTicks] = nil }
        return JSONValue.object(m).jsonString
    }

    /// `meta` with the checklist's `ticks`; nil when `meta` can't be read.
    public static func withTicks(_ meta: String?, _ ticks: Set<Int>) -> String? {
        guard var m = metaObject(meta) else { return nil }
        m[metaTicks] = ticks.isEmpty ? nil : .array(ticks.sorted().map { .int(Int64($0)) })
        return JSONValue.object(m).jsonString
    }
}

extension AnswerCard {
    /// The sources a rule card's title may come from (android CanvasLab `titleSources`): a pack's, never a user's own file,
    /// whose title is its file name (validator R-A1: the title printed bold in a shared PDF or .md).
    public static func titleSources(_ sources: [(title: String, source: String?)]) -> [String] {
        sources.filter { $0.source.map(shareable) ?? false }.map(\.title)
    }

    /// A source that may print in a shared PDF or .md (android `PressReceipt.shareable`, validator A-1): a pack's or the
    /// corpus's "Wikipedia — https://…", or a pack's bare label. For the user's own files the source is the file name
    /// ("imposto-2025.pdf"): never.
    public static func shareable(_ source: String) -> Bool {
        let s = source.kotlinTrim()
        if s.isEmpty { return false }
        if packStyle.containsMatch(in: s) { return true }
        // BOAR's own guide and FAQ (BoarPack): public text, never a user's file.
        if BoarPack.isBoarSource(s) { return true }
        return Packs.sourceLabel.values.contains(s)
    }

    private static let packStyle = Rx.javaWhole(#"[^—\n]{1,60} — https?://\S+(?: \([^)\n]{1,60}\))?"#)
}
