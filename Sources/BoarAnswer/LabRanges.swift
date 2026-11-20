import Foundation

/// Results against their reference ranges, decided in code (port of LabRanges.kt). On Android's test phone the 1.7B
/// summarized a blood test as "Total cholesterol and LDL levels are below the target thresholds" (231 against "below
/// 190", 162 against "below 130") and HDL 48 as "below … above 40". The model is given these marks with the passage, so
/// it doesn't compare numbers itself. A row the code can't read (no number, no range it knows, units that differ) is
/// left unmarked, never guessed. Pure: text in, marks out.
public enum LabRanges {
    public enum Mark: Sendable, Equatable { case within, above, below }

    /// One result: its name, value and range as the file writes them, and the mark.
    public struct Row: Sendable, Equatable {
        public let name: String
        public let value: String
        public let range: String
        public let mark: Mark
    }

    // Java's \s and \d, spelled out (ICU's are Unicode-wide).
    private static let s = "[ \\t\\n\\x0B\\f\\r]"
    private static let num = "[0-9]+(?:[.,][0-9]+)?"
    private static let unit = "[\\p{L}µ%/]+(?:/[\\p{L}]+)?"

    /// "| Test | Result | Reference |" rows, or "Test: Result (Reference)" lines.
    private static let tableRow = Rx("^\(s)*\\|\(s)*([^|]+?)\(s)*\\|\(s)*([^|]+?)\(s)*\\|\(s)*([^|]+?)\(s)*\\|")
    private static let lineRow = Rx("^\(s)*[-*•]?\(s)*([\\p{L}][^:\\n]{0,40}?)\(s)*:\(s)*(\(num)\(s)*\(unit)?)\(s)*\\(([^)\\n]{2,40})\\)")
    private static let value = Rx("^\(s)*(\(num))\(s)*(\(unit))?\(s)*$")

    // The ranges, EN and PT, each with its unit (optional).
    private static let between = Rx("^\(s)*(?:de\(s)+|entre\(s)+|from\(s)+)?(\(num))\(s)*(\(unit))?\(s)*(?:to|-|–|a|até|e|and)\(s)*(\(num))\(s)*(\(unit))?\(s)*$", ignoreCase: true)
    private static let under = Rx("^\(s)*(?:below|under|less than|lower than|up to|<|≤|<=|abaixo de|menor que|menos de|até|inferior a)\(s)*(\(num))\(s)*(\(unit))?\(s)*$", ignoreCase: true)
    private static let over = Rx("^\(s)*(?:above|over|more than|greater than|at least|>|≥|>=|acima de|maior que|mais de|superior a|pelo menos)\(s)*(\(num))\(s)*(\(unit))?\(s)*$", ignoreCase: true)

    /// Kotlin `matchEntire`: the match only when it covers the whole input.
    private static func matchEntire(_ rx: Rx, _ text: String) -> NSTextCheckingResult? {
        let len = (text as NSString).length
        guard let m = rx.re.firstMatch(in: text, options: [.anchored], range: NSRange(location: 0, length: len)),
              m.range.location == 0, m.range.length == len else { return nil }
        return m
    }

    /// Kotlin `groupValues[i]`: "" when the group did not take part.
    private static func g(_ m: NSTextCheckingResult, _ i: Int, _ text: String) -> String { m.group(i, in: text) ?? "" }

    private static func isBlank(_ s: String) -> Bool { s.allSatisfy(\.isWhitespace) }

    private static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    /// Kotlin `a.equals(b, ignoreCase = true)` (Java's regionMatches: each UTF-16 unit equal, or equal upper-cased, or
    /// equal lower-cased after that), with blank on either side counting as the same unit.
    private static func sameUnit(_ a: String?, _ b: String?) -> Bool {
        guard let a, !isBlank(a), let b, !isBlank(b) else { return true }
        let x = Array(a.utf16), y = Array(b.utf16)
        guard x.count == y.count else { return false }
        func upper(_ c: UInt16) -> String { String(utf16CodeUnits: [c], count: 1).uppercased() }
        func lower(_ s: String) -> String { s.lowercased() }
        return zip(x, y).allSatisfy { c, d in
            if c == d { return true }
            let (uc, ud) = (upper(c), upper(d))
            return uc == ud || lower(uc) == lower(ud)
        }
    }

    /// The mark for a value against a range written as the file writes it; nil when it can't tell.
    public static func mark(value valueText: String, range rangeText: String) -> Mark? {
        let vt = valueText.kotlinTrim()
        guard let v = matchEntire(value, vt), let x = number(g(v, 1, vt)) else { return nil }
        let u = g(v, 2, vt)
        let unitOf: String? = isBlank(u) ? nil : u
        let r = rangeText.kotlinTrim()
        if let m = matchEntire(between, r) {
            guard let lo = number(g(m, 1, r)), let hi = number(g(m, 3, r)) else { return nil }
            let hiUnit = g(m, 4, r)
            if lo > hi || !sameUnit(unitOf, isBlank(hiUnit) ? g(m, 2, r) : hiUnit) { return nil }
            return x < lo ? .below : (x > hi ? .above : .within)
        }
        if let m = matchEntire(under, r) {
            guard let lim = number(g(m, 1, r)) else { return nil }
            if !sameUnit(unitOf, g(m, 2, r)) { return nil }
            return x < lim ? .within : .above
        }
        if let m = matchEntire(over, r) {
            guard let lim = number(g(m, 1, r)) else { return nil }
            if !sameUnit(unitOf, g(m, 2, r)) { return nil }
            return x > lim ? .within : .below
        }
        return nil
    }

    /// Every result row in `text` the code can mark.
    public static func rows(_ text: String) -> [Row] {
        text.kotlinLines().compactMap { l in
            guard let m = tableRow.firstMatch(in: l) ?? lineRow.firstMatch(in: l) else { return nil }
            let name = g(m, 1, l).kotlinTrim(), val = g(m, 2, l).kotlinTrim(), range = g(m, 3, l).kotlinTrim()
            return mark(value: val, range: range).map { Row(name: name, value: val, range: range, mark: $0) }
        }
    }

    /// The marks as one block for the model, in Portuguese (`pt`) or English; nil when no row could be marked. Each row
    /// names the result, its value and range as written, and the mark in capitals.
    public static func note(_ text: String, pt: Bool) -> String? {
        let rs = rows(text)
        if rs.isEmpty { return nil }
        func word(_ m: Mark) -> String {
            switch m {
            case .within: pt ? "DENTRO da faixa" : "WITHIN its range"
            case .above: pt ? "ACIMA da faixa" : "ABOVE its range"
            case .below: pt ? "ABAIXO da faixa" : "BELOW its range"
            }
        }
        // Said as BOAR's, not the file's: it shows in the Sources view with the passage.
        let head = pt ? "Calculado pelo BOAR com os números deste arquivo (não está escrito no arquivo); cada resultado e a sua faixa:"
            : "Computed by BOAR from this file's own numbers (not written in the file); each result against its range:"
        // The range as a reference, "(ref. below 190 mg/dL)": "ACIMA da faixa (abaixo de 190)" came back from the model as
        // "ACIMA da faixa de abaixo de 190".
        return head + "\n" + rs.map { "- \($0.name): \($0.value), \(word($0.mark)) (ref. \($0.range))" }.joined(separator: "\n")
    }
}
