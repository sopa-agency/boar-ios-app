import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

struct SummarizeTests {
    @Test func titleCleanUpMatchesGenerateSessionTitle() throws {
        let cases = try req(Fixtures.golden("titles.json")).arr
        #expect(!cases.isEmpty)
        for c in cases {
            let pair = c.strs
            #expect(Summarize.cleanTitle(pair[0]) == pair[1], "\(pair[0])")
        }
    }

    @Test func promptsAndSettingsAsSummarizeTs() async throws {
        let calls = Log<[String]>()
        let gen = ClosureStageGenerator { system, user, n, temp, _, _ in
            calls.add([system, user, String(n), String(temp)])
            return GenResult(text: "\"Seasons on Earth\"\nmore")
        }
        // As the TS: edge quotes come off the whole reply before the first line is taken, so this one keeps its closing quote.
        #expect(try await Summarize.title(gen, firstUserMessage: "Why do we have seasons?") == "Seasons on Earth\"")
        #expect(calls.all[0][1] == "\"Why do we have seasons?\"")
        #expect(Array(calls.all[0][2...]) == ["16", "0.3"])
        _ = try await Summarize.summary(gen, turns: [ConversationTurn(role: "user", text: "Hi"), ConversationTurn(role: "assistant", text: "Hello")], previousSummary: "Old")
        #expect(calls.all[1][1] == "Existing summary:\nOld\n\nUser: Hi\nAssistant: Hello")
        #expect(Array(calls.all[1][2...]) == ["150", "0.3"])
    }
}
