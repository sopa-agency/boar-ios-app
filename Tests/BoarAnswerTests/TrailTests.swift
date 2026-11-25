import Testing

@testable import BoarAnswer

/// Android's TrailTest (rc3 bfe69c4b): the boar crosses, leaves alternating prints behind it that fade, and holds still with
/// motion reduced. Its source checks of LabHooks/BoarTrail (the closing screen's hoofprints, 50bdf593) have no iOS screen
/// to read: iOS has no Close BOAR (docs/labs-ios.md).
struct TrailTests {
    @Test func theBoarCrossesLeftToRightEachPeriodAndComesRound() {
        let xs = (0...60).map { Trail.at(Double($0) * Trail.period / 60).boar.x }
        #expect(xs.first! < 0 && xs[59] > 1)
        #expect((1..<60).allSatisfy { xs[$0] > xs[$0 - 1] })
        #expect(abs(Trail.at(1.0).boar.x - Trail.at(1.0 + Trail.period).boar.x) <= 1e-4)
    }

    @Test func printsAreBehindTheBoarInsideTheAreaAlternatingSidesFading() throws {
        for s in [2.0, 3.3, 5.9, 17.2] {
            let f = Trail.at(s)
            #expect(!f.prints.isEmpty)
            #expect(f.prints.allSatisfy { $0.x <= f.boar.x && (0...1).contains($0.x) && (0...1).contains($0.alpha) })
            #expect(f.prints.contains { $0.upper } && f.prints.contains { !$0.upper })
        }
        let f = Trail.at(5.0)
        // The newest print is the brightest.
        let newest = try #require(f.prints.map(\.x).max())
        let brightest = try #require(f.prints.max { $0.alpha < $1.alpha })
        #expect(abs(newest - brightest.x) <= 1e-6)
    }

    @Test func noPrintOutlivesItsFade() {
        #expect(Trail.at(40.0).prints.count <= Int(Trail.fade / Trail.step) + 1)
    }

    @Test func withMotionReducedItIsOneCalmFrame() {
        let a = Trail.at(1.0, still: true)
        let b = Trail.at(99.0, still: true)
        #expect(a == b)
        #expect(a.prints.allSatisfy { $0.alpha == 1 })
    }
}
