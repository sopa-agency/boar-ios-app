import Testing

@testable import BoarAnswer

/// Boar Nomad's arithmetic (CompassLab.kt has no unit test; these pin the port to its formulas).
struct CompassMathTests {
    @Test func theFirstReadingIsTakenAsItIs() {
        #expect(CompassMath.follow(0, reading: 237, first: true) == 237)
    }

    @Test func laterReadingsMoveAFractionOfTheShortestWayRound() {
        // 10° → 20°: 15 % of +10°.
        #expect(abs(CompassMath.follow(10, reading: 20, first: false) - 11.5) < 1e-9)
        // 359° → 1°: +2° the short way, not -358°.
        let h = CompassMath.follow(359, reading: 1, first: false)
        #expect(abs(h - 359.3) < 1e-9)
        // 1° → 359°: -2°, wrapping below zero.
        #expect(abs(CompassMath.follow(1, reading: 359, first: false) - 0.7) < 1e-9)
        // It converges on a steady reading.
        var x = 90.0
        for _ in 0..<200 { x = CompassMath.follow(x, reading: 300, first: false) }
        #expect(abs(x - 300) < 0.01)
    }

    @Test func theNumberMovesInWholeDegreesOnlyAfterADegree() {
        #expect(CompassMath.shown(45.6, previous: 45) == 45)
        #expect(CompassMath.shown(46.0, previous: 45) == 46)
        #expect(CompassMath.shown(46.5, previous: 45) == 47)
        #expect(CompassMath.shown(359.7, previous: 0) == 0)
        #expect(CompassMath.shown(359.4, previous: 1) == 359)
    }

    @Test func eightCardinalDirectionsEach45Wide() {
        #expect(CompassMath.cardinal(0) == "n")
        #expect(CompassMath.cardinal(22) == "n")
        #expect(CompassMath.cardinal(23) == "ne")
        #expect(CompassMath.cardinal(67) == "ne")
        #expect(CompassMath.cardinal(68) == "e")
        #expect(CompassMath.cardinal(90) == "e")
        #expect(CompassMath.cardinal(180) == "s")
        #expect(CompassMath.cardinal(225) == "sw")
        #expect(CompassMath.cardinal(337) == "nw")
        #expect(CompassMath.cardinal(338) == "n")
        #expect(CompassMath.cardinal(359) == "n")
    }
}
