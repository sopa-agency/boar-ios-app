import Foundation
import Testing

/// Android's PluginPageSwitchTest, PluginPagesTest, PluginsIconTest and PluginNamesTest, read from the Swift source
/// (the app target has no unit-test host).
struct PluginsWiringTests {
    private let list = try! AppSource.text("App/Features/Labs/LabsScreen.swift")
    private let page = try! AppSource.text("App/Features/Labs/LabPage.swift")
    private let template = try! AppSource.text("App/Features/Labs/PluginPage.swift")
    private let sheet = try! AppSource.text("App/Features/Labs/PluginsSheet.swift")
    private let store = try! AppSource.text("App/Features/Labs/Labs.swift")
    private let chat = try! AppSource.text("App/Features/Chat/ChatView.swift")
    private let setup = try! AppSource.text("App/Features/Setup/SetupGuidePages.swift")
    private let model = try! AppSource.text("App/Sources/Model/AppModel.swift")

    @Test func theSwitchIsOnEveryPageAndAsksBeforeASafetyPluginGoesOff() throws {
        #expect(page.contains("PluginSwitch(lab: lab, fromPage: true)"))
        let sw = try AppSource.slice(list, after: "struct PluginSwitch", before: "\n}\n")
        #expect(sw.contains("labs.enabled(lab.id)") && sw.contains("labs.setEnabled(lab.id, on, fromPage: fromPage)"))
        #expect(sw.contains("PluginReach.asksBeforeOff(lab.id, turningOn: on)") && sw.contains("on or off"))
        // The list and setup ask too.
        #expect(list.contains("PluginSwitch(lab: lab, fromPage: false)"))
        #expect(setup.contains("safetyOffAlert"))
    }

    @Test func noOffBannerAndOffPluginsFillNoSlot() throws {
        #expect(!page.contains("OffBanner") && !page.contains("Toggle("))
        #expect(store.contains("var active"))
        let active = try AppSource.slice(store, after: "var active", before: "\n    }\n")
        #expect(active.contains("enabled("))
    }

    @Test func tilesAndTeasersAreHiddenBehindSwitches() {
        #expect(list.contains("static let showUpcoming = false") && list.contains("static let showStatus = false"))
        #expect(!list.contains("LabTile"))
    }

    @Test func tryRowsAskEditOrCopy() {
        #expect(template.contains("ForEach(tries, id: \\.self) { TryRow(question: $0) }"))
        #expect(template.contains("askFromPlugin(question, send: true)") && template.contains("askFromPlugin(question, send: false)"))
        #expect(template.contains("Platform.copy(question)"))
        #expect(model.contains("func askFromPlugin") && model.contains("newChat()"))
    }

    @Test func everyPluginPageUsesTheTemplate() throws {
        for (file, uses) in [("CalcLab", "AnswerPage"), ("CoHazardLab", "AnswerPage"), ("DistanceLab", "AnswerPage"),
                             ("FactsLab", "AnswerPage"), ("GuardLab", "PluginPage"), ("CompassLab", "PluginPage"),
                             ("LunarLab", "PluginPage"), ("VitalsLab", "PluginPage"), ("DesignerLab", "PluginPage")] {
            let src = try AppSource.text("App/Features/Labs/Plugins/\(file).swift")
            #expect(src.contains("\(uses)("), Comment(rawValue: file))
        }
        #expect(try AppSource.portuguese("How it works") != nil && AppSource.portuguese("TRY IT") != nil)
    }

    @Test func headerIconHasNoCountAndOpensTheSheetInEveryProfile() throws {
        #expect(chat.contains("Labs.shared.headerIconShown") && chat.contains("PluginsSheet()"))
        #expect(!chat.contains("headerBadge") && !store.contains("headerBadge"))
        #expect(store.contains("RecentPlugins.pick("))
        #expect(sheet.contains("Manage plugins ›") && sheet.contains("model.selection = .screen(.labs)"))
        let press = try AppSource.text("App/Features/Labs/Plugins/PressLab.swift")
        #expect(press.contains("func headerCount()") && press.contains("in the basket"))
        for key in ["RECENT PLUGINS", "Manage plugins ›", "Plugins on", "Search plugins", "No plugin matches."] {
            #expect(try AppSource.portuguese(key) != nil, Comment(rawValue: key))
        }
    }

    @Test func noPluginNameStartsWithBoarAndNoLabsWordIsShown() throws {
        let dir = Fixtures.root.appending(path: "App/Features/Labs/Plugins")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix("Lab.swift") }
        #expect(files.count >= 9)
        let titles = /var title(?::\s*String)?\s*(?:=|\{\s*return)?\s*"([^"]*)"/
        for f in files {
            let src = try AppSource.text("App/Features/Labs/Plugins/\(f)")
            if let m = src.firstMatch(of: titles) { #expect(!m.1.hasPrefix("Boar"), Comment(rawValue: f)) }
        }
        let catalog = try AppSource.text("App/Resources/Localizable.xcstrings")
        let obj = try #require(JSONSerialization.jsonObject(with: Data(catalog.utf8)) as? [String: Any])
        let keys = try #require(obj["strings"] as? [String: Any]).keys
        for k in ["Labs", "Boar Labs", "Lab", "Open Labs"] { #expect(!keys.contains(k), Comment(rawValue: k)) }
        #expect(model.contains("case .labs: \"Plugins\"") || model.contains("\"Plugins\""))
    }
}
