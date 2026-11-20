import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// t9 0110 item 5: a question naming two or more countries gets the table's dated figures as one more source
/// (android FactsCountryContextTest.kt).
struct FactsCountryContextTests {
    private var facts: Facts { FactsTests.facts }

    @Test func twoCountriesNamedTheirPopulationAreaAndCapitalDatedAsOneSource() throws {
        let c = try #require(facts.countryContext("Compare Brazil and Russia"))
        #expect(c.title == "Facts: Brazil and Russia")
        #expect(c.body == "Brazil: population 214,211,951 (2026); area 8,515,767 km²; capital Brasília.\n"
            + "Russia: population 146,119,928 (2025); area 17,075,400 km²; capital Moscow.\n"
            + "Figures from Wikidata (CC0), offline table as of 2026-10-06.")
        #expect(c.source == "Wikidata (CC0), offline table as of 2026-10-06")
        // Not answered at once by Facts (no single property asked): the model writes it, with this source.
        #expect(facts.answer("Compare Brazil and Russia") == nil)
        #expect(try #require(facts.countryContext("Which is bigger, Japan, Germany or France?")).body.split(separator: "\n", omittingEmptySubsequences: false).count == 4)
    }

    @Test func fewerThanTwoCountriesNothingAdded() {
        for q in ["Tell me about Brazil", "Compare Paris and Brazil", "Compare cats and dogs", "What is photosynthesis?"] {
            #expect(facts.countryContext(q) == nil, "\(q)")
        }
    }

    private struct Fixed: SearchStage {
        let extra: Chunk?
        func process(query: String, chunks: [Chunk], topK: Int) throws -> [Chunk] { Array(chunks.prefix(topK)) + (extra.map { [$0] } ?? []) }
    }
    private struct Failing: SearchStage {
        struct Boom: Error {}
        func process(query: String, chunks: [Chunk], topK: Int) throws -> [Chunk] { throw Boom() }
    }
    private func chunk(_ id: String) -> Chunk { Chunk(chunkId: id, docId: id, title: id, body: id) }

    @Test func searchKeepsRoomForOneTableSourceAfterTheSearchsOwn() async throws {
        let seen = Box()
        let all = (1...8).map { chunk("c\($0)") }
        let retrieve: (String, Int) async throws -> [Chunk] = { _, k in seen.k = k; return Array(all.prefix(k)) }
        // No stage: the built-in search, topK passages.
        #expect(try await SearchStages.search([], query: "q", topK: 3, retrieve: retrieve).map(\.chunkId) == ["c1", "c2", "c3"])
        #expect(seen.k == 3)
        // A stage: twice topK to choose from, its own topK, then the one extra.
        let out = try await SearchStages.search([Fixed(extra: chunk("facts"))], query: "q", topK: 3, retrieve: retrieve)
        #expect(seen.k == 6)
        #expect(out.map(\.chunkId) == ["c1", "c2", "c3", "facts"])
        // A stage that fails is skipped: what search found stays (topK plus nothing past EXTRA).
        #expect(try await SearchStages.search([Failing()], query: "q", topK: 3, retrieve: retrieve).map(\.chunkId) == ["c1", "c2", "c3", "c4"])
    }

    /// The app target has no unit tests, so this reads its source (the Kotlin test reads FactsLab.kt and BoarServices.kt).
    @Test func theFactsLabAddsItAfterTheSearchsOwnSourcesAndEveryPathSearchesThroughTheStages() throws {
        let lab = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Labs/Plugins/FactsLab.swift"))
        #expect(lab.contains("FactsLab.table?.countryContext(query)") && lab.contains("kept + [extra]"))
        let chat = try Fixtures.text(Fixtures.root.appending(path: "App/Sources/Model/ChatController.swift"))
        #expect(chat.contains("let searchStages = Labs.shared.activeSearchStages"))
        #expect(chat.contains("stages: searchStages)") && chat.contains("stages: stages, timeoutFor"))
    }

    private final class Box: @unchecked Sendable { var k = 0 }
}
