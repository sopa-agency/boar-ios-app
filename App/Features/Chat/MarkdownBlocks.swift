import Foundation
import SwiftUI

/// Splits an answer into blocks and turns inline markdown and citations into `AttributedString`.
enum MarkdownBlocks {
    enum Block: Equatable {
        case code(String, language: String)
        case heading(Int, String)
        case bullet(String, String)
        case paragraph(String)
    }

    private static let fence = try! NSRegularExpression(pattern: "```([a-zA-Z0-9_-]*)\\n([\\s\\S]*?)(```|$)")
    private static let numbered = try! NSRegularExpression(pattern: "^([0-9]+[.)])\\s+(.*)$")
    private static let citation = try! NSRegularExpression(pattern: "\\[([0-9]+)\\](?!\\()")

    static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        let ns = text as NSString
        var last = 0
        for m in fence.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last { out += lines(ns.substring(with: NSRange(location: last, length: m.range.location - last))) }
            var code = ns.substring(with: m.range(at: 2))
            if code.hasSuffix("\n") { code.removeLast() }
            out.append(.code(code, language: ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)))
            last = m.range.location + m.range.length
        }
        if last < ns.length { out += lines(ns.substring(from: last)) }
        return out
    }

    private static func lines(_ s: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        for line in s.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flush(); continue }
            if t.hasPrefix("### ") { flush(); out.append(.heading(3, String(t.dropFirst(4)))) }
            else if t.hasPrefix("## ") { flush(); out.append(.heading(2, String(t.dropFirst(3)))) }
            else if t.hasPrefix("# ") { flush(); out.append(.heading(1, String(t.dropFirst(2)))) }
            else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") { flush(); out.append(.bullet("•", String(t.dropFirst(2)))) }
            else if let m = numbered.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) {
                flush()
                out.append(.bullet((t as NSString).substring(with: m.range(at: 1)), (t as NSString).substring(with: m.range(at: 2))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return out
    }

    /// Inline markdown, with "[n]" (1…sourceCount) turned into source links: `boar-source://n`, plus `/<answer id>` when
    /// given (the Mac routes the link back through the system and needs to know which answer it came from).
    static func inline(_ s: String, sourceCount: Int, answerId: String? = nil) -> AttributedString {
        let suffix = answerId.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }.map { "/\($0)" } ?? ""
        let ns = s as NSString
        let linked = NSMutableString(string: s)
        for m in citation.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let n = Int(ns.substring(with: m.range(at: 1))), n >= 1, n <= sourceCount else { continue }
            linked.replaceCharacters(in: m.range, with: "[\\[\(n)\\]](boar-source://\(n)\(suffix))")
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        var out = (try? AttributedString(markdown: linked as String, options: options)) ?? AttributedString(s)
        for run in out.runs {
            guard let url = run.link, url.scheme == "boar-source" else { continue }
            out[run.range].font = .footnote
            out[run.range].baselineOffset = 4
        }
        return out
    }
}
