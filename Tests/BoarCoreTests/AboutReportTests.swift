import BoarCore
import Testing

@Suite("About's bug report")
struct AboutReportTests {
    @Test("lists the plugins that are on and the device")
    func listsPluginsAndDevice() {
        let text = AboutReport.text(version: "1.0 (3)", device: "iPhone 15 · iOS 26.0", plugins: ["Boar Facts", "Boar Guard"])
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines == ["BOAR 1.0 (3)", "Device: iPhone 15 · iOS 26.0", "Plugins (2): Boar Facts, Boar Guard"])
    }

    @Test("says none when no plugin is on")
    func noPlugins() {
        let text = AboutReport.text(version: "1.0", device: "Mac", plugins: [])
        #expect(text.hasSuffix("Plugins (0): none"))
        #expect(text.contains("Plugins ("))
        #expect(text.contains("Device: "))
    }
}
