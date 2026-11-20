import Testing

@testable import BoarRouting

/// The Java behaviours the Kotlin routing code relies on: BigDecimal(x).round(MathContext(n)) and String.format("%.1f").
struct JavaCompatTests {
    @Test func bigDecimalRoundIsHalfUpOnTheExactBinaryValue() {
        // 0.0322 miles-style values and the classic 1.005 (binary 1.00499999999999989...) and 2.5 (exact tie)
        #expect(JavaNumber.roundedPlain(1.005, significant: 3) == "1")
        #expect(JavaNumber.roundedPlain(1.005, significant: 4) == "1.005")
        #expect(JavaNumber.roundedPlain(2.5, significant: 1) == "3")
        #expect(JavaNumber.roundedPlain(0.125, significant: 2) == "0.13")
        #expect(JavaNumber.roundedPlain(0.135, significant: 2) == "0.14")  // binary 0.13500000000000000888
        #expect(JavaNumber.roundedPlain(0.145, significant: 2) == "0.14")  // binary 0.14499999999999999
        #expect(JavaNumber.roundedPlain(0.0322, significant: 3) == "0.0322")
        #expect(JavaNumber.roundedPlain(0.032186880000000004, significant: 2) == "0.032")
        #expect(JavaNumber.roundedPlain(-0.125, significant: 2) == "-0.13")
        #expect(JavaNumber.roundedPlain(999.5, significant: 3) == "1000")
        #expect(JavaNumber.roundedPlain(123456.7, significant: 3) == "123000")
        #expect(JavaNumber.roundedPlain(1.0 / 3.0, significant: 15) == "0.333333333333333")
        #expect(JavaNumber.roundedPlain(0.1, significant: 15) == "0.1")
        #expect(JavaNumber.roundedPlain(0.1, significant: 20) == "0.10000000000000000555")
        #expect(JavaNumber.roundedDouble(0.0322, significant: 3) == 0.0322)
        #expect(JavaNumber.roundedDouble(-0.9996, significant: 3) == -1.0)
    }

    @Test func formatDotOneFIsHalfUpOnTheShortestDigits() {
        #expect(JavaNumber.fixed(0.25, decimals: 1) == "0.3")
        #expect(JavaNumber.fixed(0.15, decimals: 1) == "0.2")  // C's printf says 0.1
        #expect(JavaNumber.fixed(2.45, decimals: 1) == "2.5")
        #expect(JavaNumber.fixed(193.12128, decimals: 1) == "193.1")
        #expect(JavaNumber.fixed(100.0, decimals: 1) == "100.0")
        #expect(JavaNumber.fixed(-3.14, decimals: 1) == "-3.1")
        #expect(JavaNumber.fixed(1e20, decimals: 1) == "100000000000000000000.0")
        #expect(JavaNumber.fixed(0.04, decimals: 1) == "0.0")
    }

    @Test func javaRegexClassesAreAscii() {
        let d = JavaRegex(#"\d+"#)
        #expect(d.find(in: "x٣٤5")?.value == "5")  // Arabic-Indic digits are not \d in Java
        let s = JavaRegex(#"a\sb"#)
        #expect(s.containsMatch(in: "a b"))
        #expect(!s.containsMatch(in: "a\u{00A0}b"))
        #expect(JavaRegex(#"[.\s]x"#).containsMatch(in: "\tx"))
        #expect(JavaRegex(#"\d{2}"#).matches("12"))
        #expect(!JavaRegex(#"\d"#).matches("12"))
    }
}
