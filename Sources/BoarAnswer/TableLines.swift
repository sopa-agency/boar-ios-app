import Foundation

/// A Markdown table in an answer, as lines the chat can show (port of TableLines.kt; t9 2200 d: a copied blood-test table
/// showed its raw "|" pipes; the chat's Markdown draws no tables). Each data row becomes "First: second (third, fourth)",
/// the header and the separator row go. Text that isn't a table is left exactly as it was. Pure.
public enum TableLines {
    // Java's `\s` is ASCII only, spelled out here (ICU's would take Unicode spaces too).
    private static let row = Rx("^[ \\t\\n\\x{0B}\\f\\r]*\\|.*\\|[ \\t\\n\\x{0B}\\f\\r]*$")
    private static let sep = Rx("^[ \\t\\n\\x{0B}\\f\\r]*\\|?[ \\t\\n\\x{0B}\\f\\r]*:?-{3,}:?[ \\t\\n\\x{0B}\\f\\r]*(\\|[ \\t\\n\\x{0B}\\f\\r]*:?-{3,}:?[ \\t\\n\\x{0B}\\f\\r]*)+\\|?[ \\t\\n\\x{0B}\\f\\r]*$")

    /// Kotlin `Regex.matches`: the whole line, not a part of it.
    private static func matchesWhole(_ re: Rx, _ s: String) -> Bool {
        guard let m = re.firstMatch(in: s) else { return false }
        return m.range.location == 0 && m.range.length == (s as NSString).length
    }

    /// Kotlin `Char.isWhitespace`: Java's, plus the non-breaking spaces.
    private static func isWhitespace(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x09...0x0D, 0x1C...0x1F: true
        case 0x85: false
        default: [.spaceSeparator, .lineSeparator, .paragraphSeparator].contains(u.properties.generalCategory)
        }
    }

    private static func trim(_ s: [Unicode.Scalar], where drop: (Unicode.Scalar) -> Bool) -> ArraySlice<Unicode.Scalar> {
        var a = s[...]
        while let f = a.first, drop(f) { a = a.dropFirst() }
        while let l = a.last, drop(l) { a = a.dropLast() }
        return a
    }

    private static func string(_ s: ArraySlice<Unicode.Scalar>) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: s)
        return String(out)
    }

    /// Kotlin `String.lines()`: split on CRLF, LF or CR, empty lines kept.
    private static func lines(_ text: String) -> [String] {
        var out: [String] = [], cur = String.UnicodeScalarView()
        var it = Array(text.unicodeScalars)[...]
        while let u = it.popFirst() {
            if u == "\r" {
                if it.first == "\n" { it = it.dropFirst() }
                out.append(String(cur)); cur = String.UnicodeScalarView()
            } else if u == "\n" {
                out.append(String(cur)); cur = String.UnicodeScalarView()
            } else {
                cur.append(u)
            }
        }
        out.append(String(cur))
        return out
    }

    public static func of(_ text: String) -> String {
        if !text.unicodeScalars.contains("|") { return text }
        let lines = lines(text)
        var out: [String] = []
        var i = 0
        while i < lines.count {
            // A table: a row, a separator row, then rows.
            if matchesWhole(row, lines[i]), i + 1 < lines.count, matchesWhole(sep, lines[i + 1]) {
                var j = i + 2
                while j < lines.count, matchesWhole(row, lines[j]) {
                    let inner = trim(trim(Array(lines[j].unicodeScalars), where: isWhitespace).map { $0 }, where: { $0 == "|" })
                    // An empty cell keeps its place as "—" (validator P-C5: a blank result read as the range).
                    let raw = inner.split(separator: "|", omittingEmptySubsequences: false)
                        .map { string(trim(Array($0), where: isWhitespace)) }
                    let cells = raw.allSatisfy(\.isEmpty) ? [] : raw.map { $0.isEmpty ? "—" : $0 }
                    if !cells.isEmpty {
                        switch cells.count {
                        case 1: out.append(cells[0])
                        case 2: out.append("\(cells[0]): \(cells[1])")
                        default: out.append("\(cells[0]): \(cells[1]) (\(cells.dropFirst(2).joined(separator: ", ")))")
                        }
                    }
                    j += 1
                }
                i = j
                continue
            }
            out.append(lines[i])
            i += 1
        }
        return out.joined(separator: "\n")
    }
}
