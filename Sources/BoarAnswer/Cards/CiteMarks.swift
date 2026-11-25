import Foundation

/// The answer's citation marks, taken off a card (android `CiteMarks`, validator R-E2, Q-A4; t9 0115): Press renumbers the
/// answer, not the card, so a mark on a card would point at the wrong source. One strip for the model's cards and the
/// rules' cards: [1], [1, 2], [1–3], [ 1 ], [S1], [^1], 【1】. Code in backticks keeps its brackets (`items[1]`); a bare
/// items[1] is read as a mark, like "capital[1]": the two can't be told apart.
public enum CiteMarks {
    private static let n = #"(?:S|\^)?\d{1,3}"#
    private static let mark = Rx.java(#"\s*(?:\[\s*"# + n + #"(?:\s*[,–-]\s*"# + n + #")*\s*\]|【\s*"# + n + #"(?:\s*[,–-]\s*"# + n + #")*\s*】)"#)
    private static let code = Rx("`[^`\\n]*`")

    public static func strip(_ s: String) -> String {
        if !s.contains("`") { return mark.replace(s, with: "") }
        let ns = s as NSString
        var out = ""
        var at = 0
        for m in code.matches(in: s) {
            out += mark.replace(ns.substring(with: NSRange(location: at, length: m.range.location - at)), with: "")
            out += ns.substring(with: m.range)
            at = m.range.location + m.range.length
        }
        return out + mark.replace(ns.substring(from: at), with: "")
    }
}
