import Foundation
import Testing
@testable import BoarModels

@Suite struct ExitRecordTests {
    /// A fresh defaults domain per test.
    func defaults() -> UserDefaults {
        let name = "ExitRecordTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func firstLaunchIsUnsure() {
        let r = ExitRecord(defaults: defaults(), install: "/a/Boar.app")
        #expect(!r.notALoadKill(since: 1000))
    }

    @Test func killedOnScreenCounts() {
        let d = defaults()
        _ = ExitRecord(defaults: d, install: "/a/Boar.app", now: { 500 })
        let next = ExitRecord(defaults: d, install: "/a/Boar.app")
        #expect(!next.notALoadKill(since: 1000))
    }

    @Test func updateOrReinstallIsNotALoadKill() {
        let d = defaults()
        _ = ExitRecord(defaults: d, install: "/a/Boar.app")
        let next = ExitRecord(defaults: d, install: "/b/Boar.app")
        #expect(next.notALoadKill(since: 1000))
    }

    @Test func endedInTheBackgroundAfterTheLoadBegan() {
        let d = defaults()
        ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 }).enteredBackground()
        let next = ExitRecord(defaults: d, install: "/a/Boar.app")
        #expect(next.notALoadKill(since: 1000))
    }

    @Test func backBeforeTheKillCounts() {
        let d = defaults()
        let r = ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 })
        r.enteredBackground()
        r.becameActive()
        #expect(!ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: 1000))
    }

    @Test func leftBeforeTheLoadBeganCounts() {
        let d = defaults()
        ExitRecord(defaults: d, install: "/a/Boar.app", now: { 500 }).enteredBackground()
        #expect(!ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: 1000))
    }

    @Test func onlyTheLastProcessCounts() {
        let d = defaults()
        ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 }).enteredBackground()
        _ = ExitRecord(defaults: d, install: "/a/Boar.app")
        #expect(!ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: 1000))
    }

    @Test func endedInactiveIsExcusedOnce() {
        let d = defaults()
        ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 }).resignedActive()
        #expect(ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: 1000))
    }

    /// A Face ID prompt over every start load of a model too big for the phone: the second kill in a row counts.
    @Test func endedInactiveTwiceInARowCounts() {
        let d = defaults()
        ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 }).resignedActive()
        let second = ExitRecord(defaults: d, install: "/a/Boar.app", now: { 4000 })
        #expect(second.notALoadKill(since: 1000))
        second.resignedActive()
        #expect(!ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: 3000))
    }

    @Test func endedInactiveLongAfterTheLastExcuseIsExcusedAgain() {
        let d = defaults()
        let later = 1000 + ExitRecord.inactiveRepeatMs
        ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 }).resignedActive()
        let second = ExitRecord(defaults: d, install: "/a/Boar.app", now: { later + 500 })
        #expect(second.notALoadKill(since: 1000))
        second.resignedActive()
        #expect(ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: later))
    }

    @Test func activeAgainBeforeTheKillCounts() {
        let d = defaults()
        let r = ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 })
        r.resignedActive()
        r.becameActive()
        #expect(!ExitRecord(defaults: d, install: "/a/Boar.app").notALoadKill(since: 1000))
    }

    /// With the guard: a load begun on screen, then BOAR swiped away during it, doesn't block the model.
    @Test func swipeDuringLoadDoesNotBlock() {
        let d = defaults()
        let store = LoadGuardTests.Mem(), ledger = LoadGuardTests.L()
        let meta = LoadGuard.Meta(filename: "models/qwen3-1.7b.gguf", modelId: "qwen3-1.7b", label: "Qwen3 1.7B")
        let first = ExitRecord(defaults: d, install: "/a/Boar.app", now: { 2000 })
        LoadGuard(store: store, ledger: ledger, now: { 1000 }).begin(meta, previous: nil, repacked: true)
        first.enteredBackground()

        let exits = ExitRecord(defaults: d, install: "/a/Boar.app")
        let g = LoadGuard(store: store, ledger: ledger)
        g.exitWasNotLoadKill = { exits.notALoadKill(since: $0) }
        #expect(!g.isBlocked("qwen3-1.7b"))
        #expect(g.consume() == nil)
    }
}
