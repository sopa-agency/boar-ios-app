import Foundation
import Testing
@testable import BoarRouting

/// JsRegex against a real JavaScript engine: each row is (source, flags, subject, expected) with the expectation
/// produced by `new RegExp(source, flags).exec(subject)`: nil, or (match index, [whole match, groups...]).
@Suite struct JsRegexTests {
    typealias Row = (String, String, String, (Int, [String?])?)

    static let rows: [Row] = [
        ("\\bcaf\\b", "i", "caf\u{e9}", (0, ["caf"])),
        ("\\bcaf\\b", "", "cafe", nil),
        ("\\w+", "", "\u{e9}", nil),
        ("\\w+", "", "a\u{e9}", (0, ["a"])),
        ("\\d", "", "\u{663}", nil),
        ("\\d", "u", "\u{663} 7", (2, ["7"])),
        ("\\s", "", "\u{a0}", (0, ["\u{a0}"])),
        ("\\s", "", "\u{feff}", (0, ["\u{feff}"])),
        ("\\s", "", "\u{2028}", (0, ["\u{2028}"])),
        ("\\s", "", "\u{85}", nil),
        ("\\s", "", "\u{180e}", nil),
        ("\\s", "", "\u{200b}", nil),
        ("\\s", "", "\u{3000}", (0, ["\u{3000}"])),
        ("\\S+", "", "  \u{a0}ab\u{2003}", (3, ["ab"])),
        ("a.b", "", "a\u{85}b", (0, ["a\u{85}b"])),
        ("a.b", "", "a\u{a}b", nil),
        ("a.b", "", "a\u{d}b", nil),
        ("a.b", "", "a\u{2028}b", nil),
        ("a.b", "", "a\u{2029}b", nil),
        ("a.b", "", "a\u{b}b", (0, ["a\u{b}b"])),
        ("a$", "", "a\u{a}", nil),
        ("a$", "", "a", (0, ["a"])),
        ("^a", "", "b\u{a}a", nil),
        ("a$", "", "a\u{2028}", nil),
        ("k", "i", "\u{212a}", nil),
        ("k", "i", "K", (0, ["K"])),
        ("k", "iu", "\u{212a}", (0, ["\u{212a}"])),
        ("s", "i", "\u{17f}", nil),
        ("s", "iu", "\u{17f}", (0, ["\u{17f}"])),
        ("ss", "i", "\u{df}", nil),
        ("ss", "iu", "\u{df}", nil),
        ("stra\u{df}e", "i", "STRASSE", nil),
        ("\u{e9}", "i", "\u{c9}", (0, ["\u{c9}"])),
        ("\u{e9}", "iu", "\u{c9}", (0, ["\u{c9}"])),
        ("\u{e4}", "i", "\u{c4}", (0, ["\u{c4}"])),
        ("[\u{e0}-\u{ff}]", "i", "\u{c0}", (0, ["\u{c0}"])),
        ("fi", "i", "\u{fb01}", nil),
        ("i", "i", "\u{130}", nil),
        ("i", "iu", "\u{130}", nil),
        ("\u{df}", "iu", "\u{1e9e}", (0, ["\u{1e9e}"])),
        ("[a&&b]", "", "&", (0, ["&"])),
        ("[a&&b]", "", "x", nil),
        ("[$\u{20ac}]", "", "$", (0, ["$"])),
        ("[\\s-]+", "", "\u{a0}-", (0, ["\u{a0}-"])),
        ("[\\b]", "", "\u{8}", (0, ["\u{8}"])),
        ("[^\\s]+", "", "ab c", (0, ["ab"])),
        ("(?<![\\p{L}])x", "u", "\u{e9}x", nil),
        ("(?<![\\p{L}])x", "u", " x", (1, ["x"])),
        ("\\p{Lu}", "u", "aB", (1, ["B"])),
        ("[\\d.,]+", "", "1,2.3x", (0, ["1,2.3"])),
        ("\\Bb", "", "ab", (1, ["b"])),
        ("\\Bb", "", "b", nil),
        ("x*?y", "", "xxy", (0, ["xxy"])),
        ("^$", "", "", (0, [""])),
        ("a{2}", "", "aaa", (0, ["aa"])),
        ("(a)\\1", "", "aa", (0, ["aa", "a"])),
        ("a|ab", "", "ab", (0, ["a"])),
        ("(a)|(b)", "", "b", (0, ["b", nil, "b"])),
        ("(a)?b", "", "b", (0, ["b", nil])),
        ("\\.\\d{3}$", "", "1.234", (1, [".234"])),
        ("\\d{1,3}(?:[.\\s]\\d{3})+", "", "1 234 567", (0, ["1 234 567"])),
        ("\\bwales\\b", "i", "New South Wales", (10, ["Wales"])),
        ("(?<!new south )\\bwales\\b", "i", "new south wales", nil),
        ("(?<!new south )\\bwales\\b", "i", "wales", (0, ["wales"])),
        ("[\\p{L}$\u{20ac}\u{a3}]+", "iu", "US$ 5", (0, ["US$"])),
        ("\\u00e9", "", "\u{e9}", (0, ["\u{e9}"])),
        ("[\\u0300-\\u036f]", "", "e\u{301}", (1, ["\u{301}"])),
        ("\\x41", "", "A", (0, ["A"])),
        ("\\w\\b", "", "\u{e9}a\u{e9}", (1, ["a"])),
        ("x\\b", "", "x\u{e9}", (0, ["x"])),
        ("\\b", "", "\u{e9}", nil),
        ("^(why|how)\\b", "i", "How come", (0, ["How", "How"])),
        ("tl;?dr", "i", "TL;DR", (0, ["TL;DR"])),
        ("vs\\.?", "i", "vs.", (0, ["vs."])),
        ("\\d+\\s*[+\\-*/\u{d7}\u{f7}]\\s*\\d", "", "2 \u{d7} 3", (0, ["2 \u{d7} 3"])),
        ("[a-z-]+", "", "ab-c", (0, ["ab-c"])),
        ("[\\p{L}\\p{N}'\u{2019}-]*", "u", "l'o\u{2019}x-9!", (0, ["l'o\u{2019}x-9"])),
        ("a{0,2}?b", "", "aab", (0, ["aab"])),
    ]

    @Test func matchesLikeJavaScript() {
        var bad: [String] = []
        for (src, flags, input, want) in Self.rows {
            let re: JsRegex
            do { re = try JsRegex.compile(src, flags: flags) } catch { bad.append("/\(src)/\(flags) does not compile: \(error)"); continue }
            let m = re.find(in: input)
            let got: (Int, [String?])? = m.map { ($0.range.location, $0.groups) }
            let same = (want == nil && got == nil) || (want != nil && got != nil && want!.0 == got!.0 && want!.1 == got!.1)
            if !same { bad.append("/\(src)/\(flags) on \(input.debugDescription)\n    want: \(String(describing: want))\n    got:  \(String(describing: got))") }
        }
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) mismatches\n" + bad.joined(separator: "\n")))
    }

    @Test func unsupportedConstructsThrow() {
        #expect(throws: JsRegexError.self) { try JsRegex.compile("a", flags: "m") }
        #expect(throws: JsRegexError.self) { try JsRegex.compile("a", flags: "s") }
        #expect(throws: JsRegexError.self) { try JsRegex.compile("a", flags: "y") }
        #expect(throws: JsRegexError.emptyClass) { try JsRegex.compile("[]") }
        #expect(throws: JsRegexError.emptyClass) { try JsRegex.compile("[^]") }
        #expect(throws: JsRegexError.negatedShorthandInClass("S")) { try JsRegex.compile(#"[\S]"#) }
        #expect(throws: JsRegexError.trailingBackslash) { try JsRegex.compile("a\\") }
        #expect(throws: JsRegexError.self) { try JsRegex.compile("(") }
    }

    @Test func dollarIsTheEndOfInputAndNotBeforeAFinalNewline() throws {
        #expect(try JsRegex.translate("a$") == "a\\z")
        #expect(!JsRegex("a$").containsMatch(in: "a\n"))
        #expect(JsRegex("a$").containsMatch(in: "ba"))
    }

    @Test func offsetsAreUtf16() {
        let re = JsRegex("abc")
        let m = re.find(in: "\u{1F600}abc")
        #expect(m?.range.location == 2)
        #expect(re.find(in: "\u{1F600}abcabc", from: 3)?.range.location == 5)
        #expect(re.find(in: "abc", from: 4) == nil)
    }

    @Test func groupsThatDidNotTakePartAreNil() {
        let m = JsRegex("(a)|(b)").find(in: "b")
        #expect(m?.group(1) == nil)
        #expect(m?.groupValue(1) == "")
        #expect(m?.group(2) == "b")
    }

    @Test func splitKeepsEmptyAndTrailingPieces() {
        let comma = JsRegex(",")
        #expect(comma.split("a,b,") == ["a", "b", ""])
        #expect(comma.split(",a") == ["", "a"])
        #expect(comma.split("abc") == ["abc"])
        #expect(comma.split("") == [""])
        #expect(JsRegex(#"[,;]|\band\b"#, flags: "i").split("hey, what's up AND bye") == ["hey", " what's up ", " bye"])
    }

    @Test func replaceIsLiteral() {
        let re = JsRegex(#"\s+"#)
        #expect(re.replace(in: "a \u{00A0} b\tc", with: "$1\\") == "a$1\\b$1\\c")
        #expect(re.replaceFirst(in: "a  b  c", with: "_") == "a_b  c")
        #expect(re.replace(in: "none", with: "_") == "none")
        #expect(JsRegex("o").replace(in: "foo") { m in String(m.range.location) } == "f12")
    }

    @Test func findAllIsNonOverlappingAndInOrder() {
        #expect(JsRegex(#"\d+"#).findAll(in: "a1 b22 c333").map(\.value) == ["1", "22", "333"])
        #expect(JsRegex("aa").findAll(in: "aaaaa").count == 2)
    }

    @Test func caseInsensitiveStaysAsciiForAsciiSources() {
        // The Kelvin sign and the long s are not k and s without /u; with /u they are.
        #expect(!JsRegex("kelvin", flags: "i").containsMatch(in: "\u{212A}ELVIN"))
        #expect(JsRegex("kelvin", flags: "iu").containsMatch(in: "\u{212A}ELVIN"))
        // Sharp s never folds to ss, and a ligature is not its letters.
        #expect(!JsRegex("passe", flags: "i").containsMatch(in: "PA\u{00DF}E"))
        #expect(!JsRegex("official", flags: "i").containsMatch(in: "o\u{FB03}cial"))
        // Neutralising must not change what is returned: the original subject is cut.
        #expect(JsRegex("a.c", flags: "i").find(in: "xA\u{00DF}c")?.value == "A\u{00DF}c")
    }

    @Test func trimUsesJavaScriptWhitespace() {
        #expect(JsString.trim("\u{FEFF}\u{00A0} a b \u{2028}\u{3000}") == "a b")
        #expect(JsString.trim("\u{0085}a") == "\u{0085}a")
        #expect(JsString.trim("\u{200B}a") == "\u{200B}a")
        #expect(JsString.trim("") == "")
        #expect(JsString.trim(" \t\n ") == "")
        #expect(JsString.trimEnd("  a  ") == "  a")
        #expect(JsString.trimStart("  a  ") == "a  ")
    }

    @Test func kotlinStringHelpers() {
        #expect(JsString.replacingFirst("a.b.c", ".", with: "-") == "a-b.c")
        #expect(JsString.replacingFirst("abc", "", with: "") == "abc")
        #expect(JsString.replacingFirst("abc", "z", with: "y") == "abc")
        #expect(JsString.replacingAll("a.b.c", ".", with: "") == "abc")
        #expect(JsString.split("a=b=", "=") == ["a", "b", ""])
        #expect(JsString.split("abc", "=") == ["abc"])
    }
}
