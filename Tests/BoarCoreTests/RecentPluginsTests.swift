import Testing
@testable import BoarCore

/// android RecentPluginsTest.
struct RecentPluginsTests {
    private let active = ["pulse", "image", "printer", "calc", "facts", "canvas", "staged"]

    @Test func theLastUsedComeFirstOnlyPluginsThatAreOnAtMostThree() {
        #expect(RecentPlugins.pick(active: active, recent: ["canvas", "lunar", "printer"]) == ["canvas", "printer", "pulse"])
        #expect(RecentPlugins.pick(active: active, recent: []).count == 3)
        // Fewer used: the others that are on fill it, in list order.
        #expect(RecentPlugins.pick(active: active, recent: ["facts"]) == ["facts", "pulse", "image"])
    }

    @Test func usingAPluginMovesItToTheFrontTenKept() {
        let r = (1...10).map { "p\($0)" }
        #expect(RecentPlugins.used(r, id: "p5") == ["p5", "p1", "p2", "p3", "p4", "p6", "p7", "p8", "p9", "p10"])
        #expect(RecentPlugins.used(r, id: "new").count == 10)
        #expect(RecentPlugins.used(r, id: "new").first == "new")
    }

    @Test func searchFindsAPluginByItsNameOrItsLineAccentsAndCaseIgnored() {
        #expect(RecentPlugins.matches("calc", "Calculadora", "Contas do dia a dia"))
        #expect(RecentPlugins.matches("distancia", "Distância", "a distância entre duas cidades"))
        #expect(RecentPlugins.matches("PDF basket", "Press", "Collect answers into a basket and compile them into a PDF"))
        #expect(!RecentPlugins.matches("moon", "Press", "Collect answers"))
        #expect(RecentPlugins.matches("  ", "anything"))
    }
}
