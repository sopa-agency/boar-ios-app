import BoarCore
import Foundation
import Testing

/// Android's ProfileNamesTest and Wave1Test, plus what the BOAR-52 screens must keep, read from the app's Swift source (the
/// app target has no unit-test host; see `AppSource`). What needs no source is a real test (UserProfileTests).
struct SettingsProfilesWiringTests {
    private func catalogValues() throws -> [String: String] {
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(AppSource.text("App/Resources/Localizable.xcstrings").utf8)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        var pt: [String: String] = [:]
        for (key, entry) in strings {
            let unit = (((entry as? [String: Any])?["localizations"] as? [String: Any])?["pt"] as? [String: Any])?["stringUnit"] as? [String: Any]
            if let value = unit?["value"] as? String { pt[key] = value }
        }
        return pt
    }

    /// Starter and Iniciante, with the short lines; the id SIMPLE stays so stored settings do.
    @Test func starterAndIniciante() throws {
        let pt = try catalogValues()
        #expect(pt["Starter"] == "Iniciante")
        #expect(pt["Explorer"] == "Explorador")
        #expect(pt["Pro"] == "Pro")
        #expect(pt["Starter: set up the essentials."] == "Iniciante: configure o essencial.")
        #expect(pt["Explorer: discover more features."] == "Explorador: descubra mais recursos.")
        #expect(pt["Pro: advanced settings and tweaks."] == "Pro: ajustes avançados.")
        #expect(UserProfile.simple.key == "simple")
        let pills = try AppSource.text("App/Features/Settings/ProfilePills.swift")
        #expect(!pills.contains("\"Simple\""))
    }

    /// No Portuguese string translates the name Boar (the animal, "um javali", is the one allowed), and the avatars keep it.
    @Test func boarKeepsItsNameInPortuguese() throws {
        let pt = try catalogValues()
        for (key, value) in pt where key != "a wild boar" {
            #expect(value.range(of: #"\bjavali"#, options: [.regularExpression, .caseInsensitive]) == nil, "\(key): \(value)")
        }
        #expect(pt["Cosmo Boar"] == "Boar Cósmico")
    }

    /// The pills are 44 pt targets that say which is selected (android 48 dp, role Tab, selected).
    @Test func pillsAreTouchTargetsThatSaySelected() throws {
        let pills = try AppSource.text("App/Features/Settings/ProfilePills.swift")
        #expect(pills.contains("minWidth: 44, minHeight: 44"))
        #expect(pills.contains(".isSelected"))
        #expect(pills.contains("UserProfile.allCases"))
    }

    /// The agreed order and what leaves Settings (android 6a4d1fe7, 492e469b, 555e62ac): every part with a row is gated by
    /// its `SettingsPart`, Models and Knowledge are not here, and About is the last row.
    @Test func settingsShowsPartsByProfile() throws {
        let s = try AppSource.text("App/Features/Settings/SettingsScreen.swift")
        for part in ["tone", "memory", "voice", "tweaks", "profile"] {
            #expect(s.contains("SettingsPart.\(part).shown(in: profile)"), "\(part)")
        }
        #expect(s.contains("SettingsPart.experimentalShown(in: profile)"))
        #expect(!s.contains("SettingsLibrarySection"))
        let about = try #require(s.range(of: "AboutScreen()")).lowerBound
        let recovery = try #require(s.range(of: "SettingsRecoverySection(")).lowerBound
        #expect(recovery < about, "About comes after Start Over")
        #expect(s.range(of: "AboutScreen()", range: s.index(after: about)..<s.endIndex) == nil)
        // The embedding warning is the Models list's now.
        let tone = try AppSource.text("App/Features/Settings/SettingsToneSection.swift")
        #expect(!tone.contains("missingSearchModel"))
        #expect(try AppSource.text("App/Features/Models/ModelsScreen.swift").contains("missingSearchModel"))
    }

    /// Experimental: adaptive routing first, then Boarverse, then Pro's moved rows, then the Labs row.
    @Test func experimentalOrder() throws {
        let s = try AppSource.text("App/Features/Settings/SettingsExperimentalSection.swift")
        let adaptive = try #require(s.range(of: "SettingsPart.adaptiveRouting.shown(in: profile) {")).lowerBound
        let boarverse = try #require(s.range(of: "SettingsPart.boarverseSwitch.shown(in: profile) {")).lowerBound
        let moved = try #require(s.range(of: "SettingsMovedRows(bridge")).lowerBound
        let labs = try #require(s.range(of: "SettingsPart.labsSettings.shown(in: profile) {")).lowerBound
        #expect(adaptive < boarverse && boarverse < moved && moved < labs)
        // Without the experimental build the moved rows stay in Advanced.
        #expect(try AppSource.text("App/Features/Settings/AdvancedSettingsScreen.swift").contains("if !LabsBuild.experimental"))
    }

    /// Display & theme holds the Boar Avatar strip with an "All ›" box and no count; there is no section of its own.
    @Test func avatarsLiveInDisplay() throws {
        let d = try AppSource.text("App/Features/Settings/SettingsDisplaySection.swift")
        #expect(d.contains("AvatarStrip.pick("))
        #expect(d.contains("Text(\"Boar Avatar\")") && d.contains("Text(\"All ›\")"))
        #expect(d.contains("SettingsPart.avatars.shown(in: profile)"))
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: Fixtures.root.appending(path: "App/Features/Settings/SettingsAvatarsSection.swift").path))
        let pt = try catalogValues()
        #expect(pt["Boar Avatar"] == "Avatar do Boar" && pt["All ›"] == "Todos ›")
    }

    /// The tour is gone: no screen, no strings, and Start Over has no "See the tour".
    @Test func tourIsGone() throws {
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: Fixtures.root.appending(path: "App/Features/Tour").path))
        let recovery = try AppSource.text("App/Features/Settings/SettingsRecoverySection.swift")
        #expect(!recovery.localizedCaseInsensitiveContains("tour"))
        let pt = try catalogValues()
        #expect(pt["See the Tour"] == nil && pt["BOAR tour"] == nil)
    }

    /// About: the sections in order, the hold-to-copy note last, the credits name Amandita.
    @Test func aboutSections() throws {
        let a = try AppSource.text("App/Features/About/AboutScreen.swift")
        let titles = ["What BOAR is", "Your privacy", "Measure it yourself", "Links", "Plugins on", "Knowledge packs", "Core team, on X", "Credits",
                      "Tap or hold an address to copy it. Nothing opens from this page."]
        var at = a.startIndex
        for t in titles {
            let r = try #require(a.range(of: "\"\(t)\"", range: at..<a.endIndex), Comment(rawValue: t))
            at = r.upperBound
        }
        #expect(a.contains("width: 72, height: 72"))
        #expect(a.contains("AboutReport.text("))
        #expect(try AppSource.text("App/Features/About/AboutCredits.swift").contains("Amandita (@AAmandita_)"))
    }
}
