import Testing

@testable import BoarAnswer

/// The LabTools half of android UnitConversionTest.`the receipt code and the kind` and BatteryFlightNoteTest (LabTools.calc
/// is in BoarAnswer on iOS; the engine halves are in BoarRoutingTests).
struct UnitConversionLabToolsTests {
    @Test func theCalculatorToolHandsOverTheConversionWithItsReceiptCode() {
        #expect(LabTools.calc("26 miles in km", userTurns: []) == LabTools.Hit(tool: "calculator-conversion", text: "26 miles = 41.84 km (1 mile = 1.609344 km)."))
    }

    @Test func theCalculatorToolKeepsTheBatterySumAndTheNeutralFlightLine() {
        let hit = LabTools.calc("My power bank is 5,000 mAh at 3.85 V. Can I take it on a plane?", userTurns: [])
        #expect(hit?.tool == "calculator-battery")
        #expect(hit?.text == "5,000 mAh × 3.85 V ÷ 1000 = 19.25 Wh. Airlines set their battery limits in Wh, and the rules change: check your airline before you fly.")
    }
}
