import Testing

@testable import BoarRouting

/// android UnitBridgeTest.kt.
struct UnitBridgeTests {
    @Test func milesAtMphAskedInKmGivesTheTimeAndTheDistanceInKm() throws {
        let a = try #require(CalcShortcut.answer("how long to go 120 miles in km, speed in miles per hour 60 mph"))
        #expect(a.code == "calculator-rate-time")
        #expect(a.text.contains("2 hours") && a.text.contains("120 miles = 193.1 km"), "\(a.text)")
        let b = try #require(CalcShortcut.answer("how long does it take to drive 120 miles at 60 mph, answer in km"))
        #expect(b.text.contains("2 hours") && b.text.contains("193.1 km"), "\(b.text)")
    }

    @Test func kmAtMphIsConvertedToMilesFirst() throws {
        let a = try #require(CalcShortcut.answer("how many hours to travel 200 km at 50 mph?"))
        #expect(a.text.contains("2.5 hours") || a.text.contains("2 hours 29") || a.text.contains("2.49"), "\(a.text)")
        #expect(a.text.contains("200 km = 124.3 miles"), "\(a.text)")
    }

    @Test func milesAtKmPerHourIsConvertedToKm() {
        let a = CalcShortcut.answer("how long to drive 62 miles at 100 km/h?")
        #expect(a != nil && a!.text.contains("62 miles = 99.8 km"), "\(a?.text ?? "nil")")
    }

    @Test func oneUnitSystemIsLeftAsItWas() throws {
        #expect(UnitBridge.prepare("how long to drive 120 miles at 60 mph") == UnitBridge.Prepared(query: "how long to drive 120 miles at 60 mph", note: nil))
        #expect(try #require(CalcShortcut.answer("how long to drive 120 miles at 60 mph")).text
            == "About 2 hours: 120 miles ÷ 60 miles per hour = 2 hours. Computed from the numbers in your question.")
    }

    // The note and the sum keep Java's rounding: BigDecimal on the exact binary value, and %.1f on the shortest digits.
    @Test func theNoteRoundsAsJavaDoes() {
        #expect(UnitBridge.prepare("how long to drive 0.02 miles at 100 km/h").note == "0.02 miles = 0.032 km")
        #expect(UnitBridge.prepare("how long to drive 0.15 km at 50 mph").note == "0.15 km = 0.093 miles")
        #expect(UnitBridge.prepare("how long to drive 62 miles at 100 km/h").note == "62 miles = 99.8 km")
        #expect(UnitBridge.prepare("how long to drive 160.9344 km at 50 mph").note == "160.9 km = 100 miles")
    }
}
