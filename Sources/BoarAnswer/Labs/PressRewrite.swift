import Foundation

/// Press's source marks (android engine `labs/PressRewrite.kt`, the mark half). The receipt counts which sources a
/// changed answer still cites with `marks`; "Ask BOAR to rewrite it" (its prompts and the clean-up of what the model
/// wrote) joins this file with the rewrite itself.
public enum PressRewrite {
    /// A source mark in any shape a model writes (validator G-2): [5], [ 5 ], [1, 5], [1-5], [5;6], [S5], [^5], 【5】.
    /// Up to three letters may stand before a number; three digits at most, so a year in brackets is not a mark.
    /// (Java's `\s` and `\d` are ASCII: spelled out.)
    static let anyMark = try! NSRegularExpression(pattern:
        #"[\[【][ \t\n\x{0B}\f\r]*\^?[A-Za-z]{0,3}[ \t\n\x{0B}\f\r]*[0-9]{1,3}(?:[ \t\n\x{0B}\f\r]*[-–,;][ \t\n\x{0B}\f\r]*\^?[A-Za-z]{0,3}[ \t\n\x{0B}\f\r]*[0-9]{1,3})*[ \t\n\x{0B}\f\r]*[\]】]"#)
    private static let digits = try! NSRegularExpression(pattern: "[0-9]{1,3}")
    private static let dash = try! NSRegularExpression(pattern: "[-–]")

    /// The numbers one mark stands for: a range 1-5 is every number in it (at most 50).
    static func numbersIn(_ mark: String) -> [Int] {
        let trimSet: Set<Character> = ["[", "]", "【", "】", " "]
        var body = Substring(mark)
        while let f = body.first, trimSet.contains(f) { body.removeFirst() }
        while let l = body.last, trimSet.contains(l) { body.removeLast() }
        var out: [Int] = []
        for part in body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == ";" }).map(String.init) {
            let ns = part as NSString
            let n = digits.matches(in: part, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range)) }
            let hasDash = dash.firstMatch(in: part, range: NSRange(location: 0, length: ns.length)) != nil
            if n.count == 2 && hasDash && n[1] >= n[0] && n[1] - n[0] < 50 { out += Array(n[0]...n[1]) } else { out += n }
        }
        return out
    }

    /// The source marks in a text, each once, whatever their shape.
    public static func marks(_ text: String) -> Set<Int> {
        let ns = text as NSString
        return Set(anyMark.matches(in: text, range: NSRange(location: 0, length: ns.length)).flatMap { numbersIn(ns.substring(with: $0.range)) })
    }

    /// New text written from the user's own words must not cite what the passage didn't: a [n] that wasn't there before
    /// is taken out. Marks the passage had stay, written back plainly: [1, 5] with only 1 known becomes [1].
    public static func dropNewMarks(_ before: String, _ after: String) -> String {
        let had = marks(before)
        let kept = PressText.replace(anyMark, in: after) { m in
            var seen = Set<Int>()
            return numbersIn(m).filter { seen.insert($0).inserted && had.contains($0) }.map { "[\($0)]" }.joined()
        }
        return kept.replacingOccurrences(of: #" +([.,;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression).kotlinTrim()
    }

    /// A mark that was there is missing, or a new one appeared: the screen says "Some source marks changed".
    public static func marksChanged(_ before: String, _ after: String) -> Bool { marks(before) != marks(after) }
}

/// Small regex helpers the Press files share.
enum PressText {
    /// Kotlin `Regex.replace(input) { transform }`: each match's text through `f`.
    static func replace(_ re: NSRegularExpression, in s: String, _ f: (String) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    /// Kotlin `Regex.replace(input) { transform }` with the match's groups.
    static func replaceGroups(_ re: NSRegularExpression, in s: String, _ f: ([String?]) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { i -> String? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            out += f(groups)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}
