import Foundation
import Testing

@testable import BoarCore

/// Boar Vitals' per-core load (DevicePulseLab.kt has no unit test; it reads clocks, which iOS doesn't give apps).
struct CoreLoadTests {
    private func t(_ user: UInt64, _ system: UInt64, _ idle: UInt64, _ nice: UInt64 = 0) -> CoreLoad.Ticks {
        CoreLoad.Ticks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func theBusyShareOfTheTicksInBetween() {
        let load = CoreLoad.load(before: [t(100, 50, 850), t(0, 0, 0)], after: [t(130, 60, 910), t(0, 0, 100)])
        // Core 0: 30 + 10 busy of 100 ticks. Core 1: all idle.
        #expect(load.count == 2)
        #expect(abs((load[0] ?? -1) - 0.4) < 1e-12)
        #expect(load[1] == 0)
    }

    @Test func niceCountsAsBusy() {
        #expect(CoreLoad.load(before: [t(0, 0, 0, 0)], after: [t(10, 0, 10, 20)]) == [0.75])
    }

    @Test func noTicksAMissingCoreOrAWrapGiveNoValue() {
        // No ticks in between, a core only in the second snapshot, a counter that went backwards.
        let load = CoreLoad.load(before: [t(5, 5, 5), t(9, 9, 9)], after: [t(5, 5, 5), t(1, 9, 20), t(1, 1, 1)])
        #expect(load.count == 3)
        #expect(load.allSatisfy { $0 == nil })
    }

    @Test func thisMacReportsEveryCore() {
        let a = CoreLoad.read()
        #expect(a.count == ProcessInfo.processInfo.processorCount)
        // Busy work between two snapshots: every value is a share, and the ticks only grow.
        var x = 0.0
        for i in 0..<2_000_000 { x += Double(i % 7) }
        #expect(x > 0)
        let b = CoreLoad.read()
        for v in CoreLoad.load(before: a, after: b) { if let v { #expect(v >= 0 && v <= 1) } }
        #expect(zip(a, b).allSatisfy { $0.idle <= $1.idle && $0.user <= $1.user })
    }
}
