import Foundation
import Testing
@testable import BoarRouting

/// JsNumber against values produced by a real JavaScript engine (Number(), String(), toLocaleString).
@Suite struct JsNumberTests {
    typealias Loc = (en2: String, pt2: String, en0: String, pt3: String)

    static let rows: [(Double, String, Loc?)] = [
        (0.0, "0", ("0", "0", "0", "0")),
        (1.0, "1", ("1", "1", "1", "1")),
        (-1.0, "-1", ("-1", "-1", "-1", "-1")),
        (0.5, "0.5", ("0.5", "0,5", "1", "0,5")),
        (1.5, "1.5", ("1.5", "1,5", "2", "1,5")),
        (2.5, "2.5", ("2.5", "2,5", "3", "2,5")),
        (1234.5678, "1234.5678", ("1,234.57", "1.234,57", "1,235", "1.234,568")),
        (1234567.891, "1234567.891", ("1,234,567.89", "1.234.567,89", "1,234,568", "1.234.567,891")),
        (0.0004, "0.0004", ("0", "0", "0", "0")),
        (0.0005, "0.0005", ("0", "0", "0", "0,001")),
        (0.00049999, "0.00049999", ("0", "0", "0", "0")),
        (999.9995, "999.9995", ("1,000", "1.000", "1,000", "1.000")),
        (1e+21, "1e+21", ("1,000,000,000,000,000,000,000", "1.000.000.000.000.000.000.000", "1,000,000,000,000,000,000,000", "1.000.000.000.000.000.000.000")),
        (123456789.12345679, "123456789.12345679", ("123,456,789.12", "123.456.789,12", "123,456,789", "123.456.789,123")),
        (-0.0, "0", ("-0", "-0", "-0", "-0")),
        (0.30000000000000004, "0.30000000000000004", ("0.3", "0,3", "0", "0,3")),
        (100.0, "100", ("100", "100", "100", "100")),
        (1e-7, "1e-7", ("0", "0", "0", "0")),
        (2450.0, "2450", ("2,450", "2.450", "2,450", "2.450")),
        (1000000.0, "1000000", ("1,000,000", "1.000.000", "1,000,000", "1.000.000")),
        (1.2345678901234567e19, "12345678901234567000", ("12,345,678,901,234,567,000", "12.345.678.901.234.567.000", "12,345,678,901,234,567,000", "12.345.678.901.234.567.000")),
        (0.045, "0.045", ("0.05", "0,05", "0", "0,045")),
        (1.005, "1.005", ("1.01", "1,01", "1", "1,005")),
        (8.345, "8.345", ("8.35", "8,35", "8", "8,345")),
        (31.362000000000002, "31.362000000000002", ("31.36", "31,36", "31", "31,362")),
        (9.416033333333333, "9.416033333333333", ("9.42", "9,42", "9", "9,416")),
        (4.35, "4.35", ("4.35", "4,35", "4", "4,35")),
        (0.000001, "0.000001", ("0", "0", "0", "0")),
        (123.456, "123.456", ("123.46", "123,46", "123", "123,456")),
        (0.000003, "0.000003", ("0", "0", "0", "0")),
        (9007199254740992, "9007199254740992", ("9,007,199,254,740,992", "9.007.199.254.740.992", "9,007,199,254,740,992", "9.007.199.254.740.992")),
        (9007199254740994, "9007199254740994", ("9,007,199,254,740,994", "9.007.199.254.740.994", "9,007,199,254,740,994", "9.007.199.254.740.994")),
        (0.3333333333333333, "0.3333333333333333", ("0.33", "0,33", "0", "0,333")),
        (5e-324, "5e-324", nil),
        (1.7976931348623157e+308, "1.7976931348623157e+308", nil),
        (2.2250738585072014e-308, "2.2250738585072014e-308", nil),
        (1.5e-323, "1.5e-323", nil),
    ]

    @Test func stringMatchesJavaScript() {
        for (v, want, _) in Self.rows {
            #expect(JsNumber.toString(v) == want, "String(\(v))")
        }
        #expect(JsNumber.toString(.nan) == "NaN")
        #expect(JsNumber.toString(.infinity) == "Infinity")
        #expect(JsNumber.toString(-.infinity) == "-Infinity")
        #expect(JsNumber.toString(-2.5) == "-2.5")
    }

    @Test func toLocaleStringMatchesIcu() {
        for (v, _, loc) in Self.rows {
            guard let loc else { continue }
            #expect(JsNumber.locale(v, pt: false, maxFractionDigits: 2) == loc.en2, "en-US 2 \(v)")
            #expect(JsNumber.locale(v, pt: true, maxFractionDigits: 2) == loc.pt2, "pt-BR 2 \(v)")
            #expect(JsNumber.locale(v, pt: false, maxFractionDigits: 0) == loc.en0, "en-US 0 \(v)")
            #expect(JsNumber.locale(v, pt: true, maxFractionDigits: 3) == loc.pt3, "pt-BR 3 \(v)")
        }
        #expect(JsNumber.locale(.nan, pt: false) == "NaN")
        #expect(JsNumber.locale(.infinity, pt: true) == "\u{221E}")
        #expect(JsNumber.locale(-.infinity, pt: true) == "-\u{221E}")
    }

    static let parseRows: [(String, String)] = [
        ("", "0"), ("  12  ", "12"), ("0x1F", "31"), ("0b101", "5"), ("0o17", "15"), ("1e3", "1000"), (".5", "0.5"), ("5.", "5"),
        ("-Infinity", "-Infinity"), ("Infinity", "Infinity"), ("+Infinity", "Infinity"), ("abc", "NaN"), ("1,5", "NaN"),
        ("0x", "NaN"), ("1_000", "NaN"), ("+.5e-2", "0.005"), ("0xFFFFFFFFFFFFFFFFF", "295147905179352830000"),
        ("0b1111111111111111111111111111111111111111111111111111111111111111111111", "1.1805916207174113e+21"),
        ("0o777777777777777777777777777777", "1.2379400392853803e+27"), ("1e999", "Infinity"), ("-1e999", "-Infinity"),
        ("00012", "12"), ("1e", "NaN"), ("1.e2", "100"), ("- 1", "NaN"), ("1 2", "NaN"), ("\u{00A0}12\u{FEFF}", "12"),
        ("0X1f", "31"), ("1E-2", "0.01"), ("+", "NaN"), ("-", "NaN"), (".", "NaN"), ("e5", "NaN"), ("0x1.8", "NaN"),
    ]

    @Test func parseMatchesNumber() {
        for (s, want) in Self.parseRows {
            #expect(JsNumber.toString(JsNumber.parse(s)) == want, "Number(\(s.debugDescription))")
        }
    }

    @Test func roundIsMathRound() {
        #expect(JsNumber.round(2.5) == 3)
        #expect(JsNumber.round(-2.5) == -2)
        #expect(JsNumber.round(0.49999999999999994) == 0)
        #expect(JsNumber.round(-0.4).sign == .minus)
        #expect(JsNumber.round(-0.5).sign == .minus)
        #expect(JsNumber.round(-0.6) == -1)
        #expect(JsNumber.round(.infinity) == .infinity)
        #expect(JsNumber.round(.nan).isNaN)
    }
}
