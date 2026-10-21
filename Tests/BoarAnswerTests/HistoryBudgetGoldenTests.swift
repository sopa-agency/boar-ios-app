import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// The history budget must match src/routing/historyBudget.ts exactly (scripts/export-native-golden-history.mjs).
struct HistoryBudgetGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("history-budget.json") }

    private func turns(_ a: JSONValue) -> [ConversationTurn] {
        a.arr.map { ConversationTurn(role: $0["role"]!.str!, text: $0["text"]!.str!) }
    }

    @Test func leadSentences() throws {
        let cases = try req(g["lead"]).arr
        #expect(cases.count > 400)
        for c in cases {
            let text = c["text"]!.str!
            let max = c["maxTokens"]!.int
            #expect(HistoryBudget.leadSentences(text, maxTokens: max) == c["out"]!.str!, "\(max): \(text.prefix(60))")
        }
    }

    @Test func budgetedHistory() throws {
        let cases = try req(g["budget"]).arr
        #expect(cases.count > 30)
        for (i, c) in cases.enumerated() {
            let opts = c["opts"]!
            let got = HistoryBudget.budget(
                turns(c["turns"]!), budgetTokens: opts["budgetTokens"]?.intValue ?? HistoryBudget.budgetTokens,
                answerTokens: opts["answerTokens"]?.intValue ?? HistoryBudget.answerTokens
            )
            #expect(got == turns(c["out"]!), "case \(i)")
        }
    }

    @Test func theLatestExchangeAlwaysGoesInEvenOverBudget() {
        let long = [ConversationTurn(role: "user", text: String(repeating: "q", count: 3000)), ConversationTurn(role: "assistant", text: String(repeating: "a", count: 3000))]
        #expect(HistoryBudget.budget(long).count == 2)
        let short = [ConversationTurn(role: "user", text: "Hi"), ConversationTurn(role: "assistant", text: "Short.")]
        #expect(HistoryBudget.budget(short) == short)
    }
}
