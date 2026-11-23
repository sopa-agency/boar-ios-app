import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// Live tok/s has its own switch, off by default (android LiveSpeedSettingTest, rc3 0978191f).
struct LiveSpeedSettingTests {
    @Test func offByDefaultAKeptOnHoldsAndResetBringsItBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-speed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("settings.json")
        let s = AppSettings(store: JSONFileKeyValueStore(url: f))
        #expect(!s.showLiveSpeed)
        s.showLiveSpeed = true
        #expect(AppSettings(store: JSONFileKeyValueStore(url: f)).showLiveSpeed)
        #expect(AppSettings.preferenceKeys.contains("showLiveSpeed"))
        s.resetPreferences()
        #expect(!AppSettings(store: JSONFileKeyValueStore(url: f)).showLiveSpeed)
    }

    @Test func theSwitchLivesInDisplayAndThePillShowsOnlyWhileGenerating() throws {
        let display = try AppSource.text("App/Features/Settings/SettingsDisplaySection.swift")
        #expect(display.contains("showLiveSpeed"))
        #expect(try AppSource.portuguese("Show speed while answering") != nil)
        let view = try AppSource.text("App/Features/Chat/ChatView.swift")
        #expect(view.contains("chat.liveSpeed && chat.activity == .generating"))
        let ctl = try AppSource.text("App/Sources/Model/ChatController.swift")
        #expect(ctl.contains("liveSpeed = services.settings.showLiveSpeed"))
    }
}
