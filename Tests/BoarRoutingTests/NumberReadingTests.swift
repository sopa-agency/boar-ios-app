import Foundation
import Testing

@testable import BoarRouting

/// android NumberReadingTest.kt. t9 0330 (adam: "send number fix"): "27.000 mAh 3,7 V no avião" read as 27 mAh, 1000
/// times off. A number is read by the question's other numbers first, its language second; a battery's mAh is a whole
/// count everywhere.
struct NumberReadingTests {
    private func calc(_ q: String) -> String? { CalcShortcut.answer(q)?.text }

    @Test func theThreeCasesOfTheNote() {
        #expect(calc("27.000 mAh 3,7 V no avião") == "27.000 mAh × 3,7 V ÷ 1000 = 99,9 Wh." + Calculators.flightNotePT)
        #expect(calc("27,000 mAh 3.7 V no avião, posso levar?") == "27.000 mAh × 3,7 V ÷ 1000 = 99,9 Wh." + Calculators.flightNotePT)
        #expect(calc("27.000 mAh at 3.7 V on a plane") == "27,000 mAh × 3.7 V ÷ 1000 = 99.9 Wh." + Calculators.flightNoteEN)
    }

    @Test func whatWorkedKeepsWorking() throws {
        #expect(calc("Meu power bank é de 5.000 mAh a 3,85 V. Quantos watt-hora isso dá?") == "5.000 mAh × 3,85 V ÷ 1000 = 19,25 Wh.")
        #expect(calc("My power bank is 5,000 mAh at 3.85 V. How many watt-hours is that?") == "5,000 mAh × 3.85 V ÷ 1000 = 19.25 Wh.")
        #expect(try #require(calc("Meu carro alugado faz 7,5 litros a cada 100 km. Quanto isso dá em milhas por galão americano?")).hasPrefix("7,5 L/100 km = 31,36"))
        #expect(try #require(calc("My rental car uses 7.5 litres per 100 km. How much is that in US miles per gallon?")).hasPrefix("7.5 L/100 km = 31.36"))
        // "2.450 km" with no other number: the language decides.
        #expect(abs(Calculators.parseNumber("2.450", pt: Calculators.readsComma("2.450 km in miles", pt: false)) - 2.45) < 1e-9)
        #expect(abs(Calculators.parseNumber("2.450", pt: Calculators.readsComma("2.450 km em milhas", pt: true)) - 2450.0) < 1e-9)
        for pt in [false, true] {
            #expect(abs(Calculators.parseNumber("1,200.5", pt: pt) - 1200.5) < 1e-9)
            #expect(abs(Calculators.parseNumber("1.200,5", pt: pt) - 1200.5) < 1e-9)
        }
    }

    @Test func theConversionReadsItsNumberByTheQuestionsOtherNumbersToo() throws {
        // "1,5" says the comma is decimal: "2.450 km" is 2450 km, in an English sentence.
        #expect(try #require(calc("1,5 kg and 2.450 km in miles")).hasPrefix("2,450 km = "))
        // "1.5" says the dot is decimal: "2,450 km" is 2450 km, in a Portuguese one.
        #expect(try #require(calc("1.5 kg e 2,450 km em milhas")).hasPrefix("2.450 km = "))
    }

    @Test func theDecimalMarkFromTheQuestionsOwnNumbers() {
        let cases: [(String, Character?)] = [
            ("27.000 mAh 3,7 V", ","), ("27,000 mAh 3.7 V", "."), ("1.200,5 reais", ","), ("1,200.5 dollars", "."),
            ("3,85 and 3.7", nil), ("2.450 km", nil), ("26 miles in km", nil), ("5.000 mAh a 3,85 V", ","), ("5,000 mAh at 3.85 V", "."),
        ]
        for (q, want) in cases { #expect(Calculators.decimalMark(q) == want, "\(q)") }
        #expect(Calculators.decimalMark("no numbers here") == nil)
    }

    @Test func aDateNeverDecidesTheThousandsSeparator_validatorB1() {
        // The date is skipped: the language decides "2.450" as before.
        for q in ["2.450 baht no dia 14.11", "2.450 baht no dia 3.12", "2.450 baht em 14.11.2026", "2.450 baht, vencimento 05.01"] {
            #expect(Calculators.decimalMark(q) == nil, "\(q)")
        }
        #expect(Calculators.readsComma("Quanto é 2.450 baht no dia 14.11 em reais?", pt: true))
        #expect(Calculators.parseNumber("2.450", pt: Calculators.readsComma("2.450 baht no dia 14.11", pt: true)) == 2450.0)
        // Not dates: a decimal after "on", a voltage, a price with cents.
        #expect(Calculators.decimalMark("27,000 mAh on 3.7 V") == ".")
        #expect(Calculators.decimalMark("2,450 items at 12.50 each") == ".")
        #expect(Calculators.decimalMark("it costs 3.7 on average") == ".")
    }

    @Test func aPastedChainOfDigitGroupsDoesntFreezeTheSend_validatorB5() {
        let chain = String(repeating: "123 ", count: 8000) + "miles in km"
        let t0 = ContinuousClock.now
        #expect(Calculators.calculate(chain, pt: false) == nil)
        #expect(CalcShortcut.answer(chain) == nil)
        let d = ContinuousClock.now - t0
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        #if DEBUG
        let limit = 1000.0  // Kotlin's 500 ms times 2 in debug builds
        #else
        let limit = 500.0
        #endif
        #expect(ms < limit, "took \(ms) ms")
        // A calculator question under the cap still answers.
        let padded = String(repeating: "x ", count: 900) + "26 miles in km"
        #expect(padded.utf16.count < Calculators.maxQuery)
        #expect(Calculators.calculate(padded, pt: false)?.text == "26 miles = 41.84 km (1 mile = 1.609344 km).")
    }

    @Test func aTemperatureReadsItsNumberByTheQuestionsMark_validatorB6() {
        #expect(Calculators.calculate("What is 1,500 °C in Fahrenheit?", pt: false)?.text == "1,500 °C = 2,732 °F (°F = °C × 9/5 + 32).")
        // Unchanged: a plain value, a Portuguese decimal comma, a negative.
        #expect(Calculators.calculate("What is 30 °C in Fahrenheit?", pt: false)?.text == "30 °C = 86 °F (°F = °C × 9/5 + 32).")
        #expect(Calculators.calculate("Quanto é 36,6 °C em Fahrenheit?", pt: true)?.text == "36,6 °C = 97,9 °F (°F = °C × 9/5 + 32).")
        #expect(Calculators.calculate("-40 °F to Celsius", pt: false)?.text == "-40 °F = -40 °C (°C = (°F − 32) × 5/9).")
    }
}
