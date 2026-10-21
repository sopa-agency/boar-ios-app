import Foundation

/// JavaScript/Java string and regex building blocks the Kotlin port spells out so outputs match the TypeScript engine byte
/// for byte: JS's `\s` is Unicode and its `\b` ASCII-only; all offsets are UTF-16 code units (JS and JVM strings).
/// Regexes run on `NSRegularExpression` (ICU, the same syntax family as `java.util.regex`) over the string's UTF-16 view.
enum Js {
    /// JavaScript's `\s`, as a character class.
    static let ws = "[\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"
    /// `\b` before a word character, and after one (ASCII word characters only).
    static let b0 = "(?<![A-Za-z0-9_])"
    static let b1 = "(?![A-Za-z0-9_])"
    /// U+0300…U+036F, the combining diacritical marks NFD/NFKD leave behind.
    static let combining = Rx("[\\u0300-\\u036F]")

    /// JavaScript `String.prototype.trim` whitespace.
    static func isSpace(_ c: UInt16) -> Bool {
        switch c {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }

    static func trim(_ s: String) -> String { trimmed(s, start: true, end: true) }
    static func trimEnd(_ s: String) -> String { trimmed(s, start: false, end: true) }

    private static func trimmed(_ s: String, start: Bool, end: Bool) -> String {
        let u = s.utf16
        var a = u.startIndex
        var b = u.endIndex
        if start { while a < b, isSpace(u[a]) { a = u.index(after: a) } }
        if end { while b > a, isSpace(u[u.index(before: b)]) { b = u.index(before: b) } }
        return a == u.startIndex && b == u.endIndex ? s : String(s[a..<b])
    }

    static func nfd(_ s: String) -> String { s.decomposedStringWithCanonicalMapping }
    static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
    static func nfkd(_ s: String) -> String { s.decomposedStringWithCompatibilityMapping }

    /// NFD with combining marks dropped and lower case (foldText of ptLexicon.ts).
    static func fold(_ s: String) -> String { combining.replace(nfd(s), with: "").lowercased() }
}

/// Kotlin `String.trim()` (Char.isWhitespace || isSpaceChar), not JavaScript's trim.
func kotlinTrim(_ s: String) -> String {
    func ws(_ c: UInt16) -> Bool {
        switch c {
        case 0x09...0x0D, 0x1C...0x1F, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }
    let u = s.utf16
    var a = u.startIndex
    var b = u.endIndex
    while a < b, ws(u[a]) { a = u.index(after: a) }
    while b > a, ws(u[u.index(before: b)]) { b = u.index(before: b) }
    return a == u.startIndex && b == u.endIndex ? s : String(s[a..<b])
}

extension String {
    /// Length in UTF-16 code units (Kotlin/JS `length`).
    var u16Count: Int { utf16.count }

    /// Kotlin `substring(start, end)` in UTF-16 units; out-of-range bounds are clamped (Kotlin would throw).
    func u16Sub(_ start: Int, _ end: Int) -> String {
        let n = utf16.count
        let a = max(0, min(start, n)), b = max(a, min(end, n))
        if a == 0 && b == n { return self }
        return (self as NSString).substring(with: NSRange(location: a, length: b - a))
    }
    func u16Sub(from start: Int) -> String { u16Sub(start, utf16.count) }
    /// Kotlin `take(n)`.
    func u16Take(_ n: Int) -> String { u16Sub(0, max(0, n)) }
    /// Kotlin `dropLast(n)`.
    func u16DropLast(_ n: Int) -> String { u16Sub(0, utf16.count - n) }
    /// Kotlin `endsWith(suffix)` (code-unit comparison, no canonical equivalence).
    func u16EndsWith(_ suffix: String) -> Bool {
        let a = Array(utf16), b = Array(suffix.utf16)
        return a.count >= b.count && Array(a[(a.count - b.count)...]) == b
    }
    /// Kotlin `startsWith(prefix, startIndex)`.
    func u16StartsWith(_ prefix: String, at start: Int) -> Bool {
        let a = Array(utf16), b = Array(prefix.utf16)
        guard start >= 0, start + b.count <= a.count else { return false }
        return Array(a[start..<(start + b.count)]) == b
    }
}

/// One regex match: ranges in UTF-16 units of the searched string.
struct RxMatch {
    let source: NSString
    let result: NSTextCheckingResult

    var start: Int { result.range.location }
    var end: Int { result.range.location + result.range.length }
    var value: String { source.substring(with: result.range) }
    /// Kotlin `groupValues[i]`/`groups[i]?.value`: nil when the group did not take part.
    func group(_ i: Int) -> String? {
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : source.substring(with: r)
    }
    func groupRange(_ i: Int) -> NSRange? {
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : r
    }
}

/// A compiled regex (patterns are fixed in the source, so a bad one is a programmer error).
final class Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        do { re = try NSRegularExpression(pattern: pattern, options: options) } catch { fatalError("bad regex \(pattern): \(error)") }
    }

    private func full(_ ns: NSString) -> NSRange { NSRange(location: 0, length: ns.length) }

    func contains(_ s: String) -> Bool {
        let ns = s as NSString
        return re.firstMatch(in: s, options: [], range: full(ns)) != nil
    }

    func find(_ s: String) -> RxMatch? {
        let ns = s as NSString
        return re.firstMatch(in: s, options: [], range: full(ns)).map { RxMatch(source: ns, result: $0) }
    }

    func all(_ s: String) -> [RxMatch] {
        let ns = s as NSString
        return re.matches(in: s, options: [], range: full(ns)).map { RxMatch(source: ns, result: $0) }
    }

    /// Kotlin `Regex.replace(input, literal)`: every match replaced by the literal text (no `$` handling).
    func replace(_ s: String, with literal: String) -> String { replace(s) { _ in literal } }

    func replace(_ s: String, _ transform: (RxMatch) -> String) -> String {
        let ns = s as NSString
        let ms = re.matches(in: s, options: [], range: full(ns))
        if ms.isEmpty { return s }
        var out = ""
        var last = 0
        for m in ms {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform(RxMatch(source: ns, result: m))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Kotlin `Regex.replaceFirst(input, literal)`.
    func replaceFirst(_ s: String, with literal: String) -> String {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: full(ns)) else { return s }
        return ns.substring(to: m.range.location) + literal + ns.substring(from: m.range.location + m.range.length)
    }

    /// Kotlin `CharSequence.split(regex)`: trailing empty pieces are kept.
    func split(_ s: String) -> [String] {
        let ns = s as NSString
        let ms = re.matches(in: s, options: [], range: full(ns))
        if ms.isEmpty { return [s] }
        var out: [String] = []
        var last = 0
        for m in ms {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}

extension Sequence {
    /// A stable sort (Kotlin `sortedWith` is stable; ties keep their original order).
    func stableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        Array(enumerated()).sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
