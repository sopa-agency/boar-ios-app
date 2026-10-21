import BoarRouting
import Foundation

/// A reasoning model's answer split from its thinking (port of src/services/thinking.ts).
public struct SplitThinking: Sendable, Equatable {
    public var answer: String
    public var thinking: String?
    public var thinkingInProgress: Bool
    public init(answer: String, thinking: String?, thinkingInProgress: Bool) {
        self.answer = answer; self.thinking = thinking; self.thinkingInProgress = thinkingInProgress
    }
}

/// Text helpers of the answer path; each a port of the TypeScript function named in its comment, matched by golden tests.
public enum AnswerText {
    private static let markers: [(open: String, close: String)] = [("<think>", "</think>"), ("<|channel>thought", "<channel|>")]

    private static func orNil(_ s: String) -> String? { s.isEmpty ? nil : s }

    private static func split(_ text: String, _ open: String, _ close: String) -> SplitThinking? {
        guard let o = text.u16IndexOf(open) else {
            // Some templates open the block in the prompt, so only the closing marker is generated.
            guard let c = text.u16IndexOf(close) else { return nil }
            return SplitThinking(
                answer: JsString.trim(text.u16Substring(c + close.u16)), thinking: orNil(JsString.trim(text.u16Substring(0, c))),
                thinkingInProgress: false
            )
        }
        let before = text.u16Substring(0, o)
        let rest = text.u16Substring(o + open.u16)
        guard let c = rest.u16IndexOf(close) else {
            return SplitThinking(answer: JsString.trim(before), thinking: orNil(JsString.trim(rest)), thinkingInProgress: true)
        }
        return SplitThinking(
            answer: JsString.trim(before + rest.u16Substring(c + close.u16)), thinking: orNil(JsString.trim(rest.u16Substring(0, c))),
            thinkingInProgress: false
        )
    }

    /// splitThinking: `<think>…</think>` (Qwen3, LFM2.5) or `<|channel>thought…<channel|>` (Gemma 4).
    public static func splitThinking(_ text: String) -> SplitThinking {
        for (open, close) in markers {
            if let s = split(text, open, close) { return s }
        }
        // Mid-stream, only part of an opening marker may have arrived ("<|chan").
        let start = JsString.trimStart(text)
        if !start.isEmpty && markers.contains(where: { $0.open.u16HasPrefix(start) }) {
            return SplitThinking(answer: "", thinking: nil, thinkingInProgress: true)
        }
        return SplitThinking(answer: text, thinking: nil, thinkingInProgress: false)
    }

    /// stripThinking: the answer alone, for copying and history.
    public static func stripThinking(_ text: String) -> String { splitThinking(text).answer }

    private static let notSpace = "[^" + JsString.wsInner + "]"
    private static let inline = Rx("([.!?:])[ \\t]+-[ \\t]+(?=\(notSpace))")
    private static let numbered = Rx("([.!?:])[ \\t]+([0-9]{1,2})\\.[ \\t]+(?=\(notSpace))")
    private static let numberedBullet = Rx("^- ([0-9]{1,2})\\. ")

    /// splitInlineBullets (src/services/answerFormat.ts): "Takeaway. - One. - Two." on separate lines. Display only.
    public static func splitInlineBullets(_ text: String) -> String {
        let joined = text.components(separatedBy: "\n")
            .map { inline.count(in: $0) >= 2 ? inline.replace($0, with: "$1\n- ") : $0 }
            .map { numbered.count(in: $0) >= 2 ? numbered.replace($0, with: "$1\n$2. ") : $0 }
            .joined(separator: "\n")
        let lines = joined.components(separatedBy: "\n")
        // "- 1. Drop… - 2. Cover…": an ordered list, not bullets holding numbers.
        return lines.enumerated().map { i, line in
            let neighbour = (i > 0 && numberedBullet.containsMatch(in: lines[i - 1])) || (i + 1 < lines.count && numberedBullet.containsMatch(in: lines[i + 1]))
            let run = numberedBullet.containsMatch(in: line) && neighbour
            return run ? numberedBullet.replaceFirst(line, with: "$1. ") : line
        }.joined(separator: "\n")
    }

    private static let refList = Rx(
        "\\n[ \\t]*(?:\\*\\*|__)?(?:references?|sources?)(?:\\*\\*|__)?[ \\t]*:(?:\\*\\*|__)?[^\\n]*(?:\\n[\\s\\S]*)?\\z", ignoreCase: true
    )
    private static let literalN = Rx("[ \\t]*\\[n\\]", ignoreCase: true)
    private static let numberCite = Rx("[ \\t]*\\[([0-9]+)\\]")
    private static let spacePunct = Rx("[ \\t]+([.,;:!?])")
    private static let doubleSep = Rx("([,;])(\(JsString.ws)*[,;])+")
    private static let spaces = Rx("[ \\t]{2,}")

    /// Whether the digits of a citation are a number from 1 to `count` (JavaScript's Number(): one too long is out of range).
    private static func citationInRange(_ digits: String, _ count: Int) -> Bool {
        let significant = digits.drop(while: { $0 == "0" })
        if significant.isEmpty || significant.count > 18 { return false }
        guard let n = Int(significant) else { return false }
        return n >= 1 && n <= count
    }

    /// cleanCitations (src/services/citations.ts): drops invented citations ("[n]", numbers past the sources, a trailing
    /// "References:" list). `sourceCount` nil (unknown) leaves numbered citations alone. Display only.
    public static func cleanCitations(_ text: String, sourceCount: Int?) -> String {
        var out = text
        if let m = refList.firstMatch(in: out), m.range.location > 0 { out = out.u16Take(m.range.location) }
        out = literalN.replace(out, with: "")
        if let count = sourceCount {
            let snapshot = out as NSString
            out = numberCite.replace(out) { m in
                let whole = snapshot.substring(with: m.range)
                let digits = snapshot.substring(with: m.range(at: 1))
                return citationInRange(digits, count) ? whole : ""
            }
        }
        out = spacePunct.replace(out, with: "$1")
        out = doubleSep.replace(out, with: "$1")
        out = spaces.replace(out, with: " ")
        return JsString.trim(out)
    }
}
