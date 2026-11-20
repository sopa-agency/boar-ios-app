import Foundation

/// Kotlin's plain `Regex` (java.util.regex), for the Kotlin routing files that do not use `JsRegex.re`: `\d` is ASCII, `\s` is
/// only `[ \t\n\x0B\f\r]`, `$` is the end (or before a final line terminator, as ICU), `\p{L}` is Unicode. Differences
/// kept: `IGNORE_CASE` is ASCII-only in Java and Unicode simple folding under ICU (a capital accented letter such as "PÉS"
/// matches "pés" here and not on Android). Offsets are UTF-16, as in Kotlin.
struct JavaRegex: @unchecked Sendable {
    struct Match {
        /// UTF-16 range of the whole match.
        let range: NSRange
        /// Group 0 is the whole match; a group that did not take part is nil.
        let groups: [String?]
        /// UTF-16 range of each group (location NSNotFound when it did not take part).
        let ranges: [NSRange]

        var value: String { groups[0] ?? "" }
        func groupValue(_ i: Int) -> String { groups[i] ?? "" }
        func group(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    private let regex: NSRegularExpression
    private let whole: NSRegularExpression

    init(_ source: String, ignoreCase: Bool = false) {
        let p = JavaRegex.translate(source)
        let options: NSRegularExpression.Options = ignoreCase ? [.caseInsensitive] : []
        do {
            regex = try NSRegularExpression(pattern: p, options: options)
            whole = try NSRegularExpression(pattern: "\\A(?:" + p + ")\\z", options: options)
        } catch {
            fatalError("JavaRegex: \(error) in /\(source)/")
        }
    }

    private static func translate(_ source: String) -> String {
        var out = ""
        var inClass = false
        let chars = Array(source.unicodeScalars)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                let n = chars[i + 1]
                switch n {
                case "d": out += inClass ? "0-9" : "[0-9]"
                case "s": out += inClass ? " \\t\\n\\x0B\\f\\r" : "[ \\t\\n\\x0B\\f\\r]"
                default: out.unicodeScalars.append(c); out.unicodeScalars.append(n)
                }
                i += 2
                continue
            }
            if inClass {
                if c == "]" { inClass = false }
            } else if c == "[" {
                inClass = true
            }
            out.unicodeScalars.append(c)
            i += 1
        }
        return out
    }

    private func make(_ r: NSTextCheckingResult, _ ns: NSString) -> JavaRegex.Match {
        var groups: [String?] = []
        var ranges: [NSRange] = []
        for g in 0..<r.numberOfRanges {
            let rg = r.range(at: g)
            ranges.append(rg)
            groups.append(rg.location == NSNotFound ? nil : ns.substring(with: rg))
        }
        return JavaRegex.Match(range: r.range, groups: groups, ranges: ranges)
    }

    func find(in s: String, from: Int = 0) -> JavaRegex.Match? {
        let ns = s as NSString
        guard from <= ns.length else { return nil }
        return regex.firstMatch(in: s, options: [], range: NSRange(location: from, length: ns.length - from)).map { make($0, ns) }
    }

    func findAll(in s: String) -> [JavaRegex.Match] {
        let ns = s as NSString
        return regex.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { make($0, ns) }
    }

    func containsMatch(in s: String) -> Bool {
        regex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count)) != nil
    }

    /// Kotlin `Regex.matchEntire`.
    func matchEntire(_ s: String) -> JavaRegex.Match? {
        let ns = s as NSString
        return whole.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { make($0, ns) }
    }

    /// Kotlin `Regex.matches`.
    func matches(_ s: String) -> Bool { matchEntire(s) != nil }

    /// Kotlin `String.replace(regex, literal)`.
    func replace(in s: String, with replacement: String) -> String {
        let ms = findAll(in: s)
        if ms.isEmpty { return s }
        let ns = s as NSString
        var out = ""
        var cur = 0
        for m in ms {
            out += ns.substring(with: NSRange(location: cur, length: m.range.location - cur))
            out += replacement
            cur = m.range.location + m.range.length
        }
        out += ns.substring(from: cur)
        return out
    }
}

/// Java number formatting and BigDecimal rounding the Kotlin routing files call.
enum JavaNumber {
    /// `Double.toString` for NaN and the infinities.
    static func nonFinite(_ x: Double) -> String { x.isNaN ? "NaN" : (x < 0 ? "-Infinity" : "Infinity") }

    /// `BigDecimal(x).round(MathContext(p)).stripTrailingZeros().toPlainString()` (HALF_UP on the exact binary value;
    /// MathContext's default mode is HALF_UP). Finite x.
    static func roundedPlain(_ x: Double, significant p: Int) -> String {
        let neg = x < 0
        let exact = JsNumber.exact(abs(x))
        let r = exact.roundedHalfUp(significant: p).stripped()
        return (neg && !r.isZero ? "-" : "") + r.plainString()
    }

    /// `BigDecimal(x).round(MathContext(p)).toDouble()`.
    static func roundedDouble(_ x: Double, significant p: Int) -> Double {
        let neg = x < 0
        let r = JsNumber.exact(abs(x)).roundedHalfUp(significant: p)
        return neg ? -r.asDouble : r.asDouble
    }

    /// `String.format(Locale.US, "%.{n}f", x)`: Java rounds HALF_UP on the shortest decimal that reads back as x (not on
    /// the binary value as C's printf does: 0.25 gives "0.3", 0.15 gives "0.2"). Finite x.
    static func fixed(_ x: Double, decimals n: Int) -> String {
        let neg = x < 0 || (x == 0 && 1.0 / x < 0)
        var d = JsNumber.shortest(abs(x))
        if d.scale > n { d = d.roundedHalfUp(toScale: n) }
        var plain = d.stripped().plainString()
        if n > 0 {
            let frac = plain.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let have = frac.count > 1 ? frac[1].count : 0
            if have == 0 { plain += "." }
            plain += String(repeating: "0", count: n - have)
        }
        return (neg ? "-" : "") + plain
    }
}

extension JsNumber.Decimal10 {
    /// BigDecimal.round(MathContext(p)) with the default HALF_UP: the first dropped digit decides.
    func roundedHalfUp(significant p: Int) -> JsNumber.Decimal10 {
        if digits.count <= p { return self }
        var kept = Array(digits[0..<p])
        if digits[p] >= 5 { JsNumber.Decimal10.increment(&kept) }
        return JsNumber.Decimal10(digits: kept, scale: scale - (digits.count - p))
    }
}
