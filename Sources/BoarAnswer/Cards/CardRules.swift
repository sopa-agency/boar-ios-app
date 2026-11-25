import BoarRAG
import BoarRouting
import Foundation

/// A label and its value as the answer writes them ("Born" · "7 November 1867"); Kotlin's `Pair<String, String>`.
public struct CardFact: Equatable, Hashable, Sendable {
    public var label: String
    public var value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

/// One side of a comparison: its name and its points; Kotlin's `Pair<String, List<String>>`.
public struct CardSide: Equatable, Hashable, Sendable {
    public var name: String
    public var points: [String]
    public init(_ name: String, _ points: [String]) { self.name = name; self.points = points }
}

/// Cards, rules first (android `CardRules`, adam's interview, Nov 14; t9 0207): the cards an answer's own text holds,
/// found with no model. Conservative: when a pairing is not certain, no card. Every label and number is copied from the
/// text. Pure.
///
/// - Steps: 3 or more consecutive numbered lines; or 3 or more bullet lines when the question is a how-to.
/// - Table: a Markdown table.
/// - Key facts: 3 or more "Label: value" lines.
/// - Comparison: 2 to 4 lines that each start "Name:" with their points, when the question compares.
/// - Chart: 3 or more (name, number, same unit), from list lines or one enumeration ("Everest at 8,849 m, K2 at 8,611 m
///   and Kangchenjunga at 8,586 m"). Shapes: bars and table always; a pie only for percentages adding up to about 100;
///   a line only when the labels are years in order.
public enum CardRules {
    public enum Shape: String, Sendable, CaseIterable, Hashable {
        case bars = "BARS", table = "TABLE", pie = "PIE", line = "LINE", checklist = "CHECKLIST", facts = "FACTS", compare = "COMPARE"
    }

    /// One value of a series: the label and the number as the answer writes them, and the number read.
    public struct Point: Equatable, Hashable, Sendable {
        public var label: String
        public var written: String
        public var value: Double
        public init(_ label: String, _ written: String, _ value: Double) { self.label = label; self.written = written; self.value = value }
    }

    public enum Card: Equatable, Sendable {
        case steps([String])
        case table(header: [String], rows: [[String]])
        case facts([CardFact])
        case compare([CardSide])
        case chart(points: [Point], unit: String, shapes: [Shape])

        public var shapes: [Shape] {
            switch self {
            case .steps: [.checklist]
            case .table: [.table]
            case .facts: [.facts]
            case .compare: [.compare]
            case .chart(_, _, let shapes): shapes
            }
        }
    }

    private static let howTo = Rx.java(#"\b(how (do|can|to|should)|step[- ]by[- ]step|steps to|como (fa[zç]|fazer|purificar|montar|trocar|preparar|acender)|passo a passo)\b"#, ignoreCase: true)
    private static let compares = Rx.java(#"\b(compare|comparison|difference|differ|versus|vs\.?|better than|comparar|compara[çc][ãa]o|diferen[çc]a|melhor que)\b"#, ignoreCase: true)

    /// Longer than any answer (2,048 tokens is about 10,000 characters): ENUM_POINT is quadratic on a long capitalised
    /// token (validator B-7: 2.5 s at 20,000 characters, only from degenerate model output). Past it, no card.
    public static let maxAnswer = 12_000
    private static let maxSentence = 600

    public static func find(_ question: String, _ rawAnswer: String) -> [Card] {
        if rawAnswer.u16 > maxAnswer { return [] }
        // Models write "100 °C" (a narrow no-break space): the rules read it as a space (4B, the F3, Nov 14).
        let answer = rawAnswer.replacingOccurrences(of: "\u{202f}", with: " ").replacingOccurrences(of: "\u{00a0}", with: " ")
        let lines = answer.kotlinLines().map { $0.kotlinTrim() }
        var cards: [Card] = []
        if let t = table(lines) { cards.append(t) }
        let asksHowTo = howTo.containsMatch(in: question)
        if let s = steps(lines, howTo: asksHowTo) { cards.append(s) }
        let pairs = labelled(lines)
        if compares.containsMatch(in: question) && (2...4).contains(pairs.count) {
            cards.append(.compare(pairs.map { CardSide($0.label, splitPoints($0.value)) }))
        } else if pairs.count >= 3 {
            cards.append(.facts(pairs))
        }
        if let c = chart(lines, answer, question) ?? namedInQuestion(question, answer) { cards.append(c) }
        // Best first: what the question asks for, then the richest (a stable sort, as Kotlin's sortedBy).
        func rank(_ c: Card) -> Int {
            switch c {
            case .steps where asksHowTo: 0
            case .compare: 0
            case .chart: 1
            case .table: 2
            case .steps: 3
            default: 4
            }
        }
        return cards.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    // MARK: steps

    private static let numbered = Rx.java(#"^(\d{1,2})[.)]\s+(.+)$"#)
    private static let bullet = Rx.java(#"^[-*•]\s+(.+)$"#)

    private static func steps(_ lines: [String], howTo: Bool) -> Card? {
        var best: [String] = []
        var run: [String] = []
        var expect = 1
        for l in lines {
            let m = numbered.firstMatch(in: l)
            let n = m.flatMap { $0.group(1, in: l) }
            if let m, let n, Int(n) == expect {
                run.append(clean(m.group(2, in: l) ?? ""))
                expect += 1
            } else if l.isEmpty && !run.isEmpty {
                continue
            } else {
                if run.count > best.count { best = run }
                run = []
                if let m, n == "1" {
                    run.append(clean(m.group(2, in: l) ?? ""))
                    expect = 2
                } else {
                    expect = 1
                }
            }
        }
        if run.count > best.count { best = run }
        if best.count >= 3 { return .steps(best) }
        if !howTo { return nil }
        let bullets = consecutive(lines) { l in bullet.firstMatch(in: l).flatMap { $0.group(1, in: l) }.map(clean) }
        return bullets.count >= 3 ? .steps(bullets) : nil
    }

    private static func consecutive<T>(_ lines: [String], _ item: (String) -> T?) -> [T] {
        var best: [T] = []
        var run: [T] = []
        for l in lines {
            if let v = item(l) {
                run.append(v)
            } else if !l.isEmpty {
                if run.count > best.count { best = run }
                run = []
            }
        }
        return run.count > best.count ? run : best
    }

    // MARK: table

    private static let sep = Rx.javaWhole(#"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#)

    private static func table(_ lines: [String]) -> Card? {
        var i = 0
        while i < lines.count - 2 {
            defer { i += 1 }
            if !lines[i].contains("|") || !sep.containsMatch(in: lines[i + 1]) { continue }
            let header = cells(lines[i])
            let rows = lines.dropFirst(i + 2).prefix { $0.contains("|") }.map(cells).filter { $0.count == header.count }
            if header.count >= 2 && !rows.isEmpty { return .table(header: header, rows: Array(rows)) }
        }
        return nil
    }

    private static func cells(_ l: String) -> [String] {
        l.kotlinTrim().kotlinTrim(["|"]).split(separator: "|", omittingEmptySubsequences: false).map { clean(String($0).kotlinTrim()) }
    }

    // MARK: key facts and comparison

    private static let label = Rx.java(#"^(?:[-*•]\s+)?\**([\p{L}][\p{L}\d '’()/-]{0,38}?)\**\s*:\s*\**\s*(.+)$"#)

    private static func labelled(_ lines: [String]) -> [CardFact] {
        let pairs: [CardFact] = consecutive(lines) { l in
            guard let m = label.firstMatch(in: l), let name = m.group(1, in: l), let value = m.group(2, in: l),
                  !name.hasSuffix(" "), !clock(name, value) else { return nil }
            return CardFact(name.kotlinTrim(), clean(value))
        }
        return Set(pairs.map { $0.label.lowercased() }).count == pairs.count ? pairs : []
    }

    /// The colon is a clock time's ("Breakfast 08:00" read as Breakfast 08 -> 00), not a label's (validator B-10). A label
    /// whose value holds a time stays a fact: "Opening hours: 09:00 to 17:00".
    private static func clock(_ name: String, _ value: String) -> Bool {
        endsInDigit.containsMatch(in: name.kotlinTrim(["*"])) && clockValue.containsMatch(in: value.kotlinTrim())
    }
    private static let endsInDigit = Rx.java(#"\d$"#)
    /// What's left of a time after the colon: the minutes alone, with h/am/pm, or a range ("00", "30h", "00 - 13:00"); not "10 points" (R-B5).
    private static let clockValue = Rx.javaWhole(#"^\**\s*\d{2}(?:\s*(?:h|am|pm|a\.m\.|p\.m\.))?\**(?:\s*(?:-|–|to|até|a)\s*\d{1,2}(?::\d{2})?(?:\s*(?:h|am|pm))?)?\s*$"#, ignoreCase: true)

    private static let pointSplit = Rx.java(#"[;•]|,\s(?=[\p{Ll}])"#)

    private static func splitPoints(_ v: String) -> [String] {
        pointSplit.split(v).map { $0.kotlinTrim().kotlinTrimEnd(["."]) }.filter { !$0.isEmpty }
    }

    // MARK: chart

    private static let num = #"\d{1,3}(?:[.,\s]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)?"#
    /// A minus only right against the digits ("-67 °C", "−67 °C"); "Everest - 8,849 m" keeps the dash as a separator (validator B-9).
    private static let signedNum = "[-−](?=\\d)(?:" + num + ")|(?:" + num + ")"
    private static let units = "%|°C|°F|º|km²|km2|sq km|m²|km|m|cm|mm|kg|g|mg|L|ml|mL|ft|feet|metres|meters|metros|miles|milhas|years|anos|million|millions|milhões|billion|bilhões|AU|K"
    private static let listPoint = Rx.java(#"^(?:[-*•]|\d{1,2}[.)])\s+\**(\d{4}(?=\**\s*:)|[\p{L}](?:[^:\d]|(?<=\p{L})\d(?!\d*\s*(?:"# + units
        + #")\b)){0,40}?)\**\s*(?::|—|-|–|,|at|is|em|com|tem)?\s*(?:about|around|approximately|roughly|cerca de|aproximadamente)?\s*("# + signedNum
        + #")\s*("# + units + #")(?![\p{L}\d])"#, ignoreCase: true)
    private static let enumPoint = Rx.java(#"(\p{Lu}[\p{L}\d'’-]*(?:\s(?:\p{Lu}[\p{L}\d'’-]*|\d+))*)\s(?:at|is|was|with|of|em|com|tem|has)?\s*(?:about|around|approximately|roughly|cerca de)?\s*\(?("#
        + signedNum + #")\s*("# + units + #")(?![\p{L}\d])"#)
    private static let sentenceSplit = Rx.java(#"(?<=[.!?])\s+"#)

    private static func chart(_ lines: [String], _ answer: String, _ question: String) -> Card? {
        let mark = markOf(answer, question)
        func point(_ label: String, _ number: String, _ unit: String) -> Point {
            Point(clean(label).kotlinTrim().kotlinTrimEnd([":", ",", "-", "—"]), "\(number) \(unit)".kotlinTrim(), signed(number, mark))
        }
        func points(_ m: NSTextCheckingResult, _ s: String) -> (Point, String) {
            let unit = m.group(3, in: s) ?? ""
            return (point(m.group(1, in: s) ?? "", m.group(2, in: s) ?? "", unit), unit.lowercased())
        }
        let fromList = lines.compactMap { l in listPoint.firstMatch(in: l).map { points($0, l) } }
        var series = sameUnit(fromList)
        if series == nil {
            // A "sentence" past 600 characters is a degenerate run, not prose: ENUM_POINT is quadratic on one (R-E4).
            for s in sentenceSplit.split(answer) where s.u16 <= maxSentence {
                if let found = sameUnit(enumPoint.matches(in: s).map { points($0, s) }) { series = found; break }
            }
        }
        guard let (ps, unit) = series else { return nil }
        // Bars draw a length: with a value below zero they would show the coldest place as the hottest. The table keeps the sign.
        if ps.contains(where: { $0.value < 0 }) { return .chart(points: ps, unit: unit, shapes: [.table]) }
        var shapes: [Shape] = [.bars, .table]
        let sum = ps.reduce(0.0) { $0 + $1.value }
        if unit == "%" && (95.0...105.0).contains(sum) { shapes.append(.pie) }
        let years = ps.map { Int($0.label) }
        if years.allSatisfy({ $0 != nil && (1000...2999).contains($0!) }) && zip(years, years.dropFirst()).allSatisfy({ $0! < $1! }) {
            shapes.append(.line)
        }
        return .chart(points: ps, unit: unit, shapes: shapes)
    }

    /// The items the question names, one per sentence (the F3 measurement, Nov 14: "Water boils at 100 °C… Ethanol boils at
    /// approximately 78 °C… Mercury boils at 357 °C", never a list). Certain only because the question named them: each
    /// named item in the answer's first paragraph, in a sentence with exactly one number of the shared unit ("million"
    /// and "billion" read as part of the number). Three or more, or none.
    private static let scaled = Rx.java("(" + num + #")\s*(million|billion|milhões|bilhões)?\s*(%|°C|°F|km|m|kg|g|L|ft|feet|miles|metres|meters|metros|quilômetros|kilometers|kilometres)(?![\p{L}\d])"#, ignoreCase: true)
    private static let listIntro = Rx.java(#"\b(?:of|de|do|da|dos|das|are|is|between|entre)\s"#, ignoreCase: true)
    private static let andWord = Rx.java(#"\s(and|e)\s"#)
    private static let nameSplit = Rx.java(#",\s*|\s+(?:and|e)\s+"#)
    private static let paragraph = Rx.java(#"\n\s*\n"#)
    private static let parens = Rx.java(#"\([^)]*\)"#)
    private static let marks = Rx.java(#"\[\d{1,3}\]"#)
    private static let numRx = Rx.java(num)

    private static func namedInQuestion(_ question: String, _ answer: String) -> Card? {
        // The list after the last "of" / "de" / "are" that holds one ("the boiling points of water, ethanol and mercury").
        let qs = question as NSString
        guard let list = listIntro.matches(in: question).reversed()
            .map({ qs.substring(from: $0.range.location + $0.range.length).kotlinBefore("?").kotlinTrim() })
            .first(where: { $0.contains(",") || andWord.containsMatch(in: $0) }) else { return nil }
        let names = nameSplit.split(list)
            .map { $0.kotlinTrim().kotlinRemovePrefix("the ").kotlinRemovePrefix("The ").kotlinRemovePrefix("o ").kotlinRemovePrefix("a ") }
            .map { $0.kotlinBefore(" from ").kotlinBefore(",").kotlinTrim() }
            .filter { $0.u16 >= 3 }
        if names.count < 3 { return nil }
        let mark = markOf(answer, question)
        let first = paragraph.split(answer).first ?? answer
        let sentences = sentenceSplit.split(first)
        func nameRx(_ name: String) -> Rx { Rx.java("\\b" + regexLiteral(name) + "\\b", ignoreCase: true) }
        let nameRxs = Dictionary(names.map { ($0, nameRx($0)) }, uniquingKeysWith: { a, _ in a })
        func at(_ name: String, _ s: String) -> Int? { nameRxs[name]?.firstMatch(in: s)?.range.location }
        // A sentence's number belongs to the first item it names, named before the number: "Ethanol boils at 78 °C, well
        // below water" is ethanol's, never water's (validator B-8).
        func owner(_ s: String) -> String? {
            guard let firstNum = numRx.firstMatch(in: s)?.range.location else { return nil }
            var best: (String, Int)?
            for n in names {
                guard let p = at(n, s), p < firstNum else { continue }
                if best == nil || p < best!.1 { best = (n, p) }
            }
            return best?.0
        }
        func bare(_ s: String) -> String { marks.replace(parens.replace(s, with: ""), with: "") }
        var points: [(Point, String)] = []
        for name in names {
            guard let s = sentences.first(where: { owner(bare($0)) == name }) else { return nil }
            let b = bare(s)
            // Exactly one number in the sentence: a range ("54.6 million to 401 million km") is not one value.
            if numRx.count(in: b) != 1 { return nil }
            let nums = scaled.matches(in: b)
            let unitsHere = Set(nums.map { ($0.group(3, in: b) ?? "").lowercased() })
            guard let m = nums.first, unitsHere.count == 1 else { return nil }
            let g1 = m.group(1, in: b) ?? "", g2 = m.group(2, in: b) ?? "", g3 = m.group(3, in: b) ?? ""
            let scale: Double = switch g2.lowercased() {
            case "million", "milhões": 1e6
            case "billion", "bilhões": 1e9
            default: 1.0
            }
            guard let lm = nameRxs[name]?.firstMatch(in: s) else { return nil }
            let label = (s as NSString).substring(with: lm.range)
            let written = [g1, g2, g3].filter { !$0.isEmpty }.joined(separator: " ")
            points.append((Point(label.capitalizedFirst(), written, Calculators.parseNumber(g1, pt: mark) * scale), g3.lowercased()))
        }
        guard let (ps, _) = sameUnit(points) else { return nil }
        return .chart(points: ps, unit: points[0].1 == "%" ? "%" : points[0].1, shapes: [.bars, .table])
    }

    /// Three or more points with one unit and distinct labels; else none.
    private static func sameUnit(_ ps: [(Point, String)]) -> ([Point], String)? {
        if ps.count < 3 { return nil }
        let unit = ps[0].1
        if ps.contains(where: { $0.1 != unit }) || ps.contains(where: { !$0.0.value.isFinite || $0.0.label.allSatisfy(\.isWhitespace) }) { return nil }
        if Set(ps.map { $0.0.label.lowercased() }).count != ps.count { return nil }
        return (ps.map(\.0), ps[0].0.written.kotlinAfter(" ", missing: unit))
    }

    /// The number with its sign: "-67" or "−67" reads -67.0.
    private static func signed(_ n: String, _ mark: Bool) -> Double {
        if n.hasPrefix("-") || n.hasPrefix("−") { return -Calculators.parseNumber(String(n.dropFirst()), pt: mark) }
        return Calculators.parseNumber(n, pt: mark)
    }

    /// The decimal mark for a card's numbers: the answer's own numbers first (`Calculators.readsComma`), else its language,
    /// else the question's, else the app's (`AnswerLanguage.of` ends on the app setting; R-B2: "Montanhas mais altas?" says
    /// too little). A Portuguese answer's "8.849 m" is 8849 (validator B-11: "Everest: 8.849 m … Morro: 300 m" drew
    /// Everest under the hill).
    private static func markOf(_ answer: String, _ question: String) -> Bool {
        let lang = AnswerLanguage.clear(answer) ?? AnswerLanguage.of(question)
        return Calculators.readsComma(answer, pt: lang == .pt)
    }

    // Every mark shape, the model's cards' too (CiteMarks; validator Q-A4: a rules card kept "[1, 2]" in a step).
    static func clean(_ s: String) -> String {
        CiteMarks.strip(s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")).kotlinTrim()
    }
}
