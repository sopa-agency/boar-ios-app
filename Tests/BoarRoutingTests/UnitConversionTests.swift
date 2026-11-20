import Testing

@testable import BoarRouting

/// android UnitConversionTest.kt: the Calculator's plain unit conversion (adam, Nov 13: "26 miles in km" went to the
/// model, 35.8 s).
struct UnitConversionTests {
    private func en(_ q: String) -> Calculators.Calculation? { Calculators.calculate(q, pt: false) }
    private func conv(_ q: String) -> String? {
        guard let h = CalcShortcut.answer(q), h.code == "calculator-conversion" else { return nil }
        return h.text
    }

    @Test func milesToKmInEveryEnglishShape() {
        let want = "26 miles = 41.84 km (1 mile = 1.609344 km)."
        for q in [
            "26 miles in km", "26 mi to km", "convert 26 miles into kilometres", "Convert 26 miles to kilometers?",
            "how many km is 26 miles", "How many kilometres are 26 miles?", "how much is 26 miles in km?", "26mi in km",
        ] { #expect(conv(q) == want, "\(q)") }
    }

    @Test func milesToKmInEveryPortugueseShape() {
        let want = "26 milhas = 41,84 km (1 milha = 1,609344 km)."
        for q in ["26 milhas em km", "26 milhas para quilômetros", "quantos km são 26 milhas", "Quantos quilômetros são 26 milhas?", "quanto é 26 milhas em km?"] {
            #expect(conv(q) == want, "\(q)")
        }
    }

    @Test func theReverseDirections() {
        #expect(conv("41.8 km in miles") == "41.8 km = 25.97 miles (1 mile = 1.609344 km).")
        #expect(conv("80 kg in lb") == "80 kg = 176.37 lb (1 lb = 0.45359237 kg).")
        #expect(conv("6 feet in cm") == "6 feet = 182.88 cm (1 foot = 30.48 cm).")
        #expect(conv("41,8 km em milhas") == "41,8 km = 25,97 milhas (1 milha = 1,609344 km).")
        #expect(conv("quantas libras são 80 kg") == "80 kg = 176,37 lb (1 lb = 0,45359237 kg).")
        #expect(conv("6 pés em cm") == "6 pés = 182,88 cm (1 pé = 30,48 cm).")
    }

    @Test func everyUnitPairTheBriefNamesBothWays() {
        #expect(conv("180 cm in feet") == "180 cm = 5.91 feet (1 foot = 30.48 cm).")
        #expect(conv("2 m in ft") == "2 m = 6.56 feet (1 foot = 0.3048 m).")
        #expect(conv("10 inches in cm") == "10 inches = 25.4 cm (1 inch = 2.54 cm).")
        #expect(conv("30 cm to inches") == "30 cm = 11.81 inches (1 inch = 2.54 cm).")
        #expect(conv("100 yards in meters") == "100 yards = 91.44 m (1 yard = 0.9144 m).")
        #expect(conv("100 m in yards") == "100 m = 109.36 yards (1 yard = 0.9144 m).")
        #expect(conv("150 lbs to kg") == "150 lb = 68.04 kg (1 lb = 0.45359237 kg).")
        #expect(conv("100 g in oz") == "100 g = 3.53 oz (1 oz = 28.349523125 g).")
        #expect(conv("8 ounces in grams") == "8 oz = 226.8 g (1 oz = 28.349523125 g).")
        #expect(conv("10 gallons in liters") == "10 US gallons = 37.85 L (1 US gallon = 3.785411784 L).")
        #expect(conv("20 litres to US gallons") == "20 L = 5.28 US gallons (1 US gallon = 3.785411784 L).")
        #expect(conv("2 km in m") == "2 km = 2,000 m (1 km = 1,000 m).")
        #expect(conv("1.5 m to cm") == "1.5 m = 150 cm (1 m = 100 cm).")
        #expect(conv("5 polegadas em cm") == "5 polegadas = 12,7 cm (1 polegada = 2,54 cm).")
        #expect(conv("100 jardas em metros") == "100 jardas = 91,44 m (1 jarda = 0,9144 m).")
        #expect(conv("100 gramas em onças") == "100 g = 3,53 oz (1 oz = 28,349523125 g).")
        #expect(conv("10 galões em litros") == "10 galões americanos = 37,85 L (1 galão americano = 3,785411784 L).")
    }

    @Test func decimalsInBothLocalesAndASmallValueKeepsThreeSignificantDigits() {
        #expect(conv("1.5 miles in km") == "1.5 miles = 2.41 km (1 mile = 1.609344 km).")
        #expect(conv("1,5 milhas em km") == "1,5 milha = 2,41 km (1 milha = 1,609344 km).")
        #expect(conv("0.02 miles in km") == "0.02 miles = 0.0322 km (1 mile = 1.609344 km).")
        #expect(conv("0,02 milhas em km") == "0,02 milha = 0,0322 km (1 milha = 1,609344 km).")
        #expect(conv("1 mile in km") == "1 mile = 1.61 km (1 mile = 1.609344 km).")
        #expect(conv("1,200 miles in km") == "1,200 miles = 1,931.21 km (1 mile = 1.609344 km).")
    }

    @Test func inIsAPrepositionFirstAnInchOnlyBeforeToOrIn() {
        #expect(conv("5 in to cm") == "5 inches = 12.7 cm (1 inch = 2.54 cm).")
        #expect(conv("5 in in cm") == "5 inches = 12.7 cm (1 inch = 2.54 cm).")
        #expect(conv("5 inches in cm") == "5 inches = 12.7 cm (1 inch = 2.54 cm).")
        #expect(conv("26 miles in km") == "26 miles = 41.84 km (1 mile = 1.609344 km).")
        #expect(en("5 in km") == nil)
    }

    @Test func mIsAMetreOnlyAsAWholeWord() {
        #expect(en("I drove 26 miles in my car") == nil)
        #expect(en("5 min to km") == nil)
        #expect(conv("5 m to cm") == "5 m = 500 cm (1 m = 100 cm).")
    }

    @Test func sameUnitAnotherFamilyOrNoNumberNoAnswer() {
        for q in [
            "26 km in kilometres", "5 miles in miles", "5 miles in kg", "80 kg in km", "miles in km", "how many feet in a mile",
            "how many km in a marathon", "convert miles to km", "10 imperial gallons in liters", "10 UK gallons to litres",
            "I walked 5 km to the station", "What is the capital of France?",
        ] { #expect(en(q) == nil, "\(q)") }
    }

    @Test func aRateQuestionStaysWithArithmeticAndTheUnitBridge() throws {
        let a = try #require(CalcShortcut.answer("how long does it take to drive 120 miles at 60 mph, answer in km"))
        #expect(a.code == "calculator-rate-time")
        #expect(a.text.contains("2 hours") && a.text.contains("120 miles = 193.1 km"), "\(a.text)")
        let b = try #require(CalcShortcut.answer("how long to drive 62 miles at 100 km/h?"))
        #expect(b.code == "calculator-rate-time")
        #expect(b.text.contains("62 miles = 99.8 km"), "\(b.text)")
        for q in ["26 miles in km at 60 mph", "10 km in miles per hour", "100 km/h in mph", "5 km per hour in miles", "20 km por hora em milhas"] {
            #expect(en(q).flatMap { $0.kind == "conversion" ? $0 : nil } == nil, "\(q)")
        }
    }

    @Test func theTemperatureAndFuelRulesKeepTheirQuestions() throws {
        #expect(try #require(CalcShortcut.answer("What is 30 °C in Fahrenheit?")).code == "temperature-conversion")
        #expect(try #require(CalcShortcut.answer("30 mpg in l/100km")).code == "calculator-fuel-economy")
        #expect(try #require(CalcShortcut.answer("7.5 L/100 km in mpg")).code == "calculator-fuel-economy")
    }

    @Test func aHealthTurnGetsNoConversion() throws {
        #expect(try #require(CalcShortcut.answer("20 kg in lb")).code == "calculator-conversion")
        #expect(CalcShortcut.answer("20 kg in lb for my child") == nil)
        #expect(CalcShortcut.answer("20 kg in lb", userTurns: ["My daughter is sick and has a fever"]) == nil)
        #expect(CalcShortcut.answer("the patient lost 5 kg in lb?") == nil)
    }

    @Test func theReceiptCodeAndTheKind() throws {
        #expect(try #require(en("26 miles in km")).kind == "conversion")
        let hit = try #require(CalcShortcut.answer("26 miles in km"))
        #expect(hit.code == "calculator-conversion")
        // Android also asserts LabTools.calc here; LabTools lives in BoarAnswer (BoarAnswerTests covers it).
        #expect(CalcShortcut.answer("quantos km são 26 milhas") == CalcShortcut.Hit(code: "calculator-conversion", text: "26 milhas = 41,84 km (1 milha = 1,609344 km)."))
    }

    @Test func aCompoundQuantityGoesToTheModelNeverItsLastPartAlone_validatorB2() {
        for q in [
            "5 feet 10 in to cm", "5 ft 10 inches in cm", "1 lb 8 oz to kg", "1 lb and 8 oz in grams", "how many cm is 5 feet 10 inches",
            "2 libras e 3 onças em gramas",
        ] {
            #expect(conv(q) == nil, "\(q)")
            #expect(CalcShortcut.answer(q) == nil, "\(q)")
        }
        // Two quantities of different kinds are not one compound: the conversion still answers.
        #expect(conv("A 5 kg box, 10 inches to cm") == "10 inches = 25.4 cm (1 inch = 2.54 cm).")
    }

    @Test func aRangeGoesToTheModelNeverItsLastNumberAlone_validatorB3() {
        for q in [
            "between 5 and 10 miles in km", "5 to 10 miles in km", "5-10 miles in km", "5–10 kg to lb", "de 5 a 10 milhas em km",
            "entre 5 e 10 milhas em km", "3 or 4 feet in cm",
        ] {
            #expect(conv(q) == nil, "\(q)")
            #expect(CalcShortcut.answer(q) == nil, "\(q)")
        }
        // A number elsewhere in the question is not a range.
        #expect(conv("I ran 3 days and 26 miles in km is how much?") == "26 miles = 41.84 km (1 mile = 1.609344 km).")
    }

    @Test func aLeadingMinusKeepsItsSign_validatorB4() {
        #expect(conv("-5 km to miles") == "-5 km = -3.11 miles (1 mile = 1.609344 km).")
        #expect(conv("−2 kg to lb") == "-2 kg = -4.41 lb (1 lb = 0.45359237 kg).")
        // A dash between words isn't a sign; a range still goes to the model.
        #expect(conv("Route A - 5 km to miles") == "5 km = 3.11 miles (1 mile = 1.609344 km).")
        #expect(conv("5-10 km to miles") == nil)
    }

    @Test func theCompoundAndRangeHolesGoToTheModelToo_validatorRB3() {
        for q in ["5 feet plus 10 inches in cm", "how many cm are 5 feet 10", "-5 to -3 km in miles", "5 pés mais 10 polegadas em cm"] {
            #expect(conv(q) == nil, "\(q)")
        }
        // Single conversions still answer.
        #expect(conv("5 miles in km") == "5 miles = 8.05 km (1 mile = 1.609344 km).")
        #expect(conv("how many cm is 5 feet") == "5 feet = 152.4 cm (1 foot = 30.48 cm).")
        #expect(conv("I am 5 feet and about 10 inches tall; convert 10 inches to cm") == "10 inches = 25.4 cm (1 inch = 2.54 cm).")
    }
}
