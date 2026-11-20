import BoarRAG
import Testing

/// t9 0226: the Portuguese word readings that picked weak sources, fixed case by case (PtReadingsTest.kt).
@Suite struct PtReadingsTests {
    private let lx = RagTextGoldenTests.lexicon
    private func names(_ q: String) -> [String] { PtLexicon.englishNamesIn(q, lx) }

    @Test func theTidesAreTideNotSea() { #expect(names("O que causa as marés?") == ["Tide"]) }

    @Test func whyTheSkyIsBlueIsTheSkysLightNotTheColourBlue() {
        #expect(names("Por que o céu é azul?") == ["Diffuse sky radiation"])
        #expect(names("O que é a cor azul?") == ["Blue"])
    }

    @Test func aDeviceIsNotBrickworkATimeUnitNamesNothing() {
        #expect(!names("Um aparelho tem 12 GB de RAM. O sistema e o app ocupam 2 GB").contains("Brickwork"))
        #expect(names("Um trem sai às 15h40 e a viagem leva 2 horas e 35 minutos. A que horas ele chega?").allSatisfy { !["Minute", "Hour"].contains($0) })
        // "capital" keeps the lexicon's Capital city: without it the search lost Canberra (re-measure, 15 Nov).
        #expect(names("Qual é a capital da Austrália?") == ["Capital city", "Australia"])
    }

    @Test func earthsTiltIsAxialTiltSupplyAndDemandWithItsArticleIsSupplyAndDemand() {
        #expect(names("Como a inclinação da Terra cria as estações, e por que elas se invertem entre os hemisférios").contains("Axial tilt"))
        #expect(!names("Como a inclinação da Terra cria as estações").contains("Orbital inclination"))
        #expect(names("Compare como a oferta e a demanda explicam a mudança de preços").contains("Supply and demand"))
    }

    @Test func portugueseFunctionWordsAreNotSearchTermsParaCameFromPara() throws {
        let q = try #require(RagPure.buildLexicalQuery("Como as monções se formam, e por que importam para a agricultura no sul da Ásia"))
        #expect(!q.match.contains("\"para\"") && !q.match.contains("\"como\"") && !q.match.contains("\"por\""))
        // English keeps its words: OS is the operating system.
        #expect(try #require(RagPure.buildLexicalQuery("The OS and app overhead take 2GB")).match.contains("\"os\""))
    }
}
