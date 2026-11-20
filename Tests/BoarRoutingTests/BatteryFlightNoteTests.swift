import Testing

@testable import BoarRouting

/// android BatteryFlightNoteTest.kt. adam, Nov 14 (t9 0143): "maybe is accurate today, and change in future… better
/// change that?" The battery answer keeps its sum; with flight words it adds one neutral line, no yes or no, no 100 or
/// 160, no carry-on rule. Android reads it through LabTools.calc, which lives in BoarAnswer on iOS; it is CalcShortcut
/// for a question under 2,000 characters (the LabTools wrapper is covered in BoarAnswerTests).
struct BatteryFlightNoteTests {
    private func calc(_ q: String) -> String? { CalcShortcut.answer(q)?.text }

    @Test func theSumThenTheNeutralLineInEnglishAndPortuguese() {
        #expect(calc("My power bank is 5,000 mAh at 3.85 V. Can I take it on a plane?") == "5,000 mAh × 3.85 V ÷ 1000 = 19.25 Wh." + Calculators.flightNoteEN)
        #expect(calc("Meu power bank é de 5.000 mAh a 3,85 V. Posso levar no avião?") == "5.000 mAh × 3,85 V ÷ 1000 = 19,25 Wh." + Calculators.flightNotePT)
        // Without flight words, the sum alone.
        #expect(calc("A 2000 mAh battery at 3.7 V is how many Wh?") == "2,000 mAh × 3.7 V ÷ 1000 = 7.4 Wh.")
    }

    private static func digits(_ x: String) -> String { x.filter(\.isNumber) }

    @Test func noVerdictAtAnySizeAndNoNumberThatIsNotInTheQuestionOrTheResult() throws {
        let numberRe = JsRegex(#"\d[\d.,]*"#)
        let limitRe = JsRegex(#"(?<![\d.,])(100|160)(?![\d.,])"#)
        for q in ["10000 mAh 3.7 V on a plane?", "40000 mAh 3.7 V flight", "60000 mAh 3.7 V airline carry-on", "Meu power bank de 30000 mAh a 3,7 V pode ir no avião?"] {
            let a = try #require(calc(q))
            for gone in ["Yes", "Sim,", "carry-on baggage", "bagagem de mão", "not allowed", "não é permitido"] {
                #expect(!a.contains(gone), "\(q): \(gone)")
            }
            #expect(!limitRe.containsMatch(in: a), "\(q): a 100 or 160 limit")
            // Digits only, so "10,000" in the answer matches "10000" in the question.
            let numbers = Set(numberRe.findAll(in: a).map { Self.digits($0.value) })
            let head = a.components(separatedBy: " Wh.")[0]
            let result = Self.digits(head.components(separatedBy: "= ").last ?? "")
            let asked = Set(numberRe.findAll(in: q).map { Self.digits($0.value) })
            for n in numbers { #expect(asked.contains(n) || n == result || n == "1000", "\(q): \(n)") }
        }
    }
}
