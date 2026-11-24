import Foundation

// Shared by the Cards port (android engine/canvas): Kotlin's `Regex` (java.util.regex) on ICU, and the Kotlin string
// operations the card rules lean on.

extension Rx {
    /// A Kotlin `Regex` pattern on ICU: `\d` is ASCII (`[0-9]`) and `\s` only `[ \t\n\x0B\f\r]`, as in java.util.regex
    /// (ICU's would also take Unicode digits and no-break spaces). Everything else reads the same.
    static func java(_ pattern: String, ignoreCase: Bool = false) -> Rx { Rx(javaPattern(pattern), ignoreCase: ignoreCase) }

    /// For Kotlin `Regex.matches(input)`: the pattern over the whole input (`containsMatch(in:)` then answers it).
    static func javaWhole(_ pattern: String, ignoreCase: Bool = false) -> Rx {
        Rx("\\A(?:" + javaPattern(pattern) + ")\\z", ignoreCase: ignoreCase)
    }

    private static func javaPattern(_ pattern: String) -> String {
        var out = ""
        var inClass = false
        let chars = Array(pattern.unicodeScalars)
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
}

extension String {
    /// Kotlin `trim(vararg chars)`: drops these characters from both ends.
    func kotlinTrim(_ chars: Set<Character>) -> String {
        var s = Substring(self)
        while let f = s.first, chars.contains(f) { s.removeFirst() }
        while let l = s.last, chars.contains(l) { s.removeLast() }
        return String(s)
    }

    /// Kotlin `trimEnd(vararg chars)`.
    func kotlinTrimEnd(_ chars: Set<Character>) -> String {
        var s = Substring(self)
        while let l = s.last, chars.contains(l) { s.removeLast() }
        return String(s)
    }

    /// Kotlin `substringBefore(delimiter)`: all of it when the delimiter is missing.
    func kotlinBefore(_ d: String) -> String { u16IndexOf(d).map { u16Substring(0, $0) } ?? self }

    /// Kotlin `substringAfter(delimiter, missing)`.
    func kotlinAfter(_ d: String, missing: String? = nil) -> String {
        guard let i = u16IndexOf(d) else { return missing ?? self }
        return u16Substring(i + d.u16)
    }

    /// Kotlin `substringAfterLast(delimiter)`: all of it when the delimiter is missing.
    func kotlinAfterLast(_ d: String) -> String {
        let r = (self as NSString).range(of: d, options: [.literal, .backwards])
        return r.location == NSNotFound ? self : u16Substring(r.location + r.length)
    }

    /// Kotlin `removePrefix`.
    func kotlinRemovePrefix(_ p: String) -> String { hasPrefix(p) ? String(dropFirst(p.count)) : self }

    /// Kotlin `replaceFirstChar { it.uppercase() }`.
    func capitalizedFirst() -> String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}

/// Kotlin `Regex.escape` for a literal inside a pattern.
func regexLiteral(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
