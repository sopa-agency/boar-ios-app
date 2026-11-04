import Foundation
import Testing
@testable import BoarCore

/// FreeMemoryTest.kt.
@Suite struct FreeMemoryTests {
    @Test func autoAndASavedImmediatelyDontWaitAPickWaitsItsOwn() {
        #expect(FreeMemory.delayMs(nil) == 0)
        #expect(FreeMemory.delayMs(0) == 0)
        #expect(FreeMemory.delayMs(5) == 5 * 60_000)
        #expect(FreeMemory.delayMs(30) == 30 * 60_000)
        #expect(FreeMemory.delayMs(-3) == 0)
    }

    @Test func unloadsOnlyWhenOnAwayLoadedAndIdle() {
        #expect(FreeMemory.decide(enabled: true, inForeground: false, loaded: true, busy: false) == .unload)
        #expect(FreeMemory.decide(enabled: true, inForeground: false, loaded: true, busy: true) == .wait)
        #expect(FreeMemory.decide(enabled: false, inForeground: false, loaded: true, busy: false) == .skip)
        #expect(FreeMemory.decide(enabled: true, inForeground: true, loaded: true, busy: false) == .skip)
        // A model still loading counts as busy: wait for it rather than leave it in memory once loaded.
        #expect(FreeMemory.decide(enabled: true, inForeground: false, loaded: false, busy: true) == .wait)
        #expect(FreeMemory.decide(enabled: true, inForeground: false, loaded: false, busy: false) == .skip)
    }

    @Test func onAndAutoByDefaultAndResetSettingsRestoresBoth() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "boar-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appending(path: "settings.json")
        let s = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(s.freeMemoryInBackground)
        #expect(s.freeMemoryAfterMinutes == nil)
        s.freeMemoryInBackground = false
        s.freeMemoryAfterMinutes = 30
        #expect(!AppSettings(store: JSONFileKeyValueStore(url: f)).freeMemoryInBackground)
        #expect(AppSettings(store: JSONFileKeyValueStore(url: f)).freeMemoryAfterMinutes == 30)
        s.freeMemoryAfterMinutes = 0
        #expect(AppSettings(store: JSONFileKeyValueStore(url: f)).freeMemoryAfterMinutes == 0)
        s.resetPreferences()
        let again = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(again.freeMemoryInBackground)
        #expect(again.freeMemoryAfterMinutes == nil)
    }
}
