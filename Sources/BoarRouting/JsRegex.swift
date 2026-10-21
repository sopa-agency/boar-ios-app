import Foundation

/// JavaScript string helpers the routing modules rely on (the Kotlin `rag.Js` object): `trim` over JavaScript's
/// whitespace set, NFD, and the `\s` class spelled out for a regex engine.
public enum JsString {
    /// JavaScript's `\s` as a regex character class source (ECMAScript WhiteSpace + LineTerminator).
    public static let ws = #"[\t\n\u000B\f\r    -     　﻿]"#
    /// The same set without the brackets, for use inside a larger class.
    public static let wsInner = #"\t\n\u000B\f\r    -     　﻿"#

    /// JavaScript `String.prototype.trim` whitespace.
    public static func isSpace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        case 0x2000...0x200A: return true
        default: return false
        }
    }

    public static func trim(_ s: String) -> String { trimEnd(trimStart(s)) }

    public static func trimStart(_ s: String) -> String {
        var scalars = Substring(s).unicodeScalars
        while let f = scalars.first, isSpace(f) { scalars.removeFirst() }
        return String(scalars)
    }

    public static func trimEnd(_ s: String) -> String {
        var scalars = Substring(s).unicodeScalars
        while let l = scalars.last, isSpace(l) { scalars.removeLast() }
        return String(scalars)
    }

    /// Canonical decomposition (Kotlin `Normalizer.Form.NFD`).
    public static func nfd(_ s: String) -> String { s.decomposedStringWithCanonicalMapping }
    public static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    /// Kotlin `String.replaceFirst(oldValue, newValue)`: a literal replacement of the first occurrence (UTF-16 order).
    public static func replacingFirst(_ s: String, _ old: String, with new: String) -> String {
        if old.isEmpty { return new + s }
        guard let r = s.range(of: old, options: .literal) else { return s }
        return s.replacingCharacters(in: r, with: new)
    }

    /// Kotlin `String.replace(oldValue, newValue)`: every occurrence, literal.
    public static func replacingAll(_ s: String, _ old: String, with new: String) -> String {
        if old.isEmpty { return s }
        return s.replacingOccurrences(of: old, with: new, options: .literal)
    }

    /// Kotlin `String.split(delimiter)`: every piece, empty ones kept, literal delimiter.
    public static func split(_ s: String, _ delimiter: String) -> [String] {
        precondition(!delimiter.isEmpty)
        var out: [String] = []
        var start = s.startIndex
        while let r = s.range(of: delimiter, options: .literal, range: start..<s.endIndex) {
            out.append(String(s[start..<r.lowerBound]))
            start = r.upperBound
        }
        out.append(String(s[start...]))
        return out
    }
}

public enum JsRegexError: Error, Equatable, CustomStringConvertible {
    case unsupportedFlags(String)
    case emptyClass
    case negatedShorthandInClass(Character)
    case trailingBackslash
    case invalidPattern(String)

    public var description: String {
        switch self {
        case .unsupportedFlags(let f): return "unsupported JS regex flags: \(f)"
        case .emptyClass: return "empty JS character class"
        case .negatedShorthandInClass(let c): return "\\\(c) in a character class"
        case .trailingBackslash: return "pattern ends with a backslash"
        case .invalidPattern(let p): return "invalid pattern: \(p)"
        }
    }
}

/// JavaScript regular expressions on `NSRegularExpression` (ICU): the routing modules keep their TypeScript sources
/// verbatim and this translates the parts whose meaning differs. JS `\b`/`\w`/`\d` are ASCII (even with /u), `\s` is
/// Unicode whitespace, `.` stops only at \n \r U+2028 U+2029, `$` without /m is the end of input, and /i is Unicode
/// simple-case-folding (a handful of characters ICU folds to several letters, or to ASCII where JS does not, are
/// neutralised in the subject, see `multiFold` and `asciiFold`). Not handled (throws): the m/s/y flags, `[]` and `[^]`, `\S`/`\D`/`\W` inside a class.
/// Offsets and ranges are UTF-16, as in Kotlin and JavaScript.
public struct JsRegex: @unchecked Sendable {
    public struct Match: Sendable {
        /// UTF-16 range of the whole match in the subject.
        public let range: NSRange
        /// Group 0 is the whole match; a group that did not take part is nil (Kotlin `groups[i]`).
        public let groups: [String?]

        public var value: String { groups[0] ?? "" }
        /// Kotlin `groupValues[i]`: "" for a group that did not take part.
        public func groupValue(_ i: Int) -> String { groups[i] ?? "" }
        public func group(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    private static let W = "[A-Za-z0-9_]"
    private static let boundary = "(?:(?<=\(W))(?!\(W))|(?<!\(W))(?=\(W)))"
    private static let notBoundary = "(?:(?<=\(W))(?=\(W))|(?<!\(W))(?!\(W)))"
    private static let dot = #"[^\n\r  ]"#

    /// Characters ICU's case-insensitive matching folds to several letters, which JavaScript's /i never does (sharp
    /// s vs ss, ligatures, dotted capital I). Replaced one-for-one (so offsets stay valid) by a Greek letter of the
    /// same case in the copy the engine sees; results are cut from the original subject. Omitted: the polytonic Greek
    /// letters with iota subscript (multi-letter folds, never ASCII).
    private static let multiFold: [UInt16: UInt16] = {
        var m: [UInt16: UInt16] = [:]
        let lower: [UInt16] = [0x00DF, 0x0149, 0x01F0, 0x0390, 0x03B0, 0x0587, 0x1E96, 0x1E97, 0x1E98, 0x1E99, 0x1E9A,
                               0xFB00, 0xFB01, 0xFB02, 0xFB03, 0xFB04, 0xFB05, 0xFB06, 0xFB13, 0xFB14, 0xFB15, 0xFB16, 0xFB17]
        let upper: [UInt16] = [0x0130, 0x1E9E]
        for u in lower { m[u] = 0x03C9 }
        for u in upper { m[u] = 0x03A9 }
        return m
    }()

    /// Long s and the Kelvin sign fold to ASCII s and k under ICU. JavaScript's /i without /u does not fold them
    /// (Canonicalize never maps a non-ASCII letter to ASCII); with /u it does (simple case folding).
    private static let asciiFold: [UInt16: UInt16] = [0x017F: 0x03C9, 0x212A: 0x03A9]

    private let regex: NSRegularExpression
    private let neutral: [UInt16: UInt16]
    /// The translated ICU pattern (for diagnostics and tests).
    public let pattern: String

    /// Compiles a JS source; throws for constructs the translation does not support.
    public static func compile(_ source: String, flags: String = "") throws -> JsRegex {
        let translated = try translate(source, flags: flags)
        do {
            var neutral: [UInt16: UInt16] = [:]
            if flags.contains("i") {
                neutral = multiFold
                if !flags.contains("u") { neutral.merge(asciiFold) { a, _ in a } }
            }
            // The same letters in the pattern itself ("straße" must not match "STRASSE").
            let icu = neutral.isEmpty ? translated : String(decoding: translated.utf16.map { neutral[$0] ?? $0 }, as: UTF16.self)
            let re = try NSRegularExpression(pattern: icu, options: [])
            return JsRegex(regex: re, neutral: neutral, pattern: translated)
        } catch {
            throw JsRegexError.invalidPattern(translated)
        }
    }

    private init(regex: NSRegularExpression, neutral: [UInt16: UInt16], pattern: String) {
        self.regex = regex
        self.neutral = neutral
        self.pattern = pattern
    }

    /// For the routing modules' constants: a pattern that fails to translate is a programming error.
    public init(_ source: String, flags: String = "") {
        do {
            self = try JsRegex.compile(source, flags: flags)
        } catch {
            fatalError("JsRegex: \(error) in /\(source)/\(flags)")
        }
    }

    /// The ICU source for a JS regex source and its flags.
    public static func translate(_ source: String, flags: String = "") throws -> String {
        guard flags.allSatisfy({ "giu".contains($0) }) else { throw JsRegexError.unsupportedFlags(flags) }
        var sb = ""
        if flags.contains("i") { sb += "(?i)" }
        let chars = Array(source.unicodeScalars)
        var inClass = false
        var i = 0
        func put(_ c: Unicode.Scalar) { sb.unicodeScalars.append(c) }
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                guard i + 1 < chars.count else { throw JsRegexError.trailingBackslash }
                let n = chars[i + 1]
                if !inClass {
                    switch n {
                    case "s": sb += JsString.ws
                    case "S": sb += "[^" + JsString.wsInner + "]"
                    case "b": sb += boundary
                    case "B": sb += notBoundary
                    case "d": sb += "[0-9]"
                    case "D": sb += "[^0-9]"
                    case "w": sb += W
                    case "W": sb += "[^A-Za-z0-9_]"
                    default: put(c); put(n)
                    }
                } else {
                    switch n {
                    case "s": sb += JsString.wsInner
                    case "b": sb += "\\x08"
                    case "d": sb += "0-9"
                    case "w": sb += "A-Za-z0-9_"
                    case "S", "D", "W": throw JsRegexError.negatedShorthandInClass(Character(n))
                    default: put(c); put(n)
                    }
                }
                i += 2
                continue
            }
            if inClass {
                switch c {
                case "]": inClass = false; put(c)
                case "[": sb += "\\["
                case "&": sb += "\\&"
                case "$": sb += "\\$"
                default: put(c)
                }
            } else {
                switch c {
                case "[":
                    inClass = true
                    put(c)
                    if i + 1 < chars.count, chars[i + 1] == "^" { put("^"); i += 1 }
                    if i + 1 < chars.count, chars[i + 1] == "]" { throw JsRegexError.emptyClass }
                case ".": sb += dot
                case "$": sb += "\\z"
                default: put(c)
                }
            }
            i += 1
        }
        return sb
    }

    // MARK: matching

    private func subject(_ s: String) -> String {
        guard !neutral.isEmpty, s.utf16.contains(where: { neutral[$0] != nil }) else { return s }
        let units = s.utf16.map { neutral[$0] ?? $0 }
        return String(decoding: units, as: UTF16.self)
    }

    private func match(_ r: NSTextCheckingResult, in original: NSString) -> Match {
        var groups: [String?] = []
        groups.reserveCapacity(r.numberOfRanges)
        for g in 0..<r.numberOfRanges {
            let rg = r.range(at: g)
            groups.append(rg.location == NSNotFound ? nil : original.substring(with: rg))
        }
        return Match(range: r.range, groups: groups)
    }

    /// Kotlin `Regex.find`: the first match at or after UTF-16 offset [from].
    public func find(in s: String, from: Int = 0) -> Match? {
        let ns = s as NSString
        guard from <= ns.length else { return nil }
        let r = regex.firstMatch(in: subject(s), options: [], range: NSRange(location: from, length: ns.length - from))
        return r.map { match($0, in: ns) }
    }

    /// Kotlin `Regex.containsMatchIn`.
    public func containsMatch(in s: String) -> Bool {
        regex.firstMatch(in: subject(s), options: [], range: NSRange(location: 0, length: s.utf16.count)) != nil
    }

    /// Kotlin `Regex.findAll`.
    public func findAll(in s: String) -> [Match] {
        let ns = s as NSString
        return regex.matches(in: subject(s), options: [], range: NSRange(location: 0, length: ns.length)).map { match($0, in: ns) }
    }

    /// Kotlin `Regex.replace(input, replacement)` for a LITERAL replacement (no `$1` / `\` expansion).
    public func replace(in s: String, with replacement: String) -> String {
        replace(in: s) { _ in replacement }
    }

    /// Kotlin `Regex.replace(input) { transform }`.
    public func replace(in s: String, transform: (Match) -> String) -> String {
        let ms = findAll(in: s)
        if ms.isEmpty { return s }
        let ns = s as NSString
        var out = ""
        var cur = 0
        for m in ms {
            out += ns.substring(with: NSRange(location: cur, length: m.range.location - cur))
            out += transform(m)
            cur = m.range.location + m.range.length
        }
        out += ns.substring(from: cur)
        return out
    }

    /// Kotlin `String.replaceFirst(regex, replacement)` for a literal replacement.
    public func replaceFirst(in s: String, with replacement: String) -> String {
        guard let m = find(in: s) else { return s }
        let ns = s as NSString
        return ns.substring(to: m.range.location) + replacement + ns.substring(from: m.range.location + m.range.length)
    }

    /// Kotlin `Regex.split(input)`: every piece including empty and trailing ones; no match gives the input.
    public func split(_ s: String) -> [String] {
        let ms = findAll(in: s)
        if ms.isEmpty { return [s] }
        let ns = s as NSString
        var out: [String] = []
        var cur = 0
        for m in ms {
            out.append(ns.substring(with: NSRange(location: cur, length: m.range.location - cur)))
            cur = m.range.location + m.range.length
        }
        out.append(ns.substring(from: cur))
        return out
    }
}
