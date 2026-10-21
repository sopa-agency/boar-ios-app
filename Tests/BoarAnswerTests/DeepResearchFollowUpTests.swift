import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// "conclusion" after a research answer was split as written, searched for "conclusion" and refused (X6, Oct 13).
struct DeepResearchFollowUpTests {
    let history = ConversationHistory(turns: [
        ConversationTurn(role: "user", text: "How does the greenhouse effect warm the planet?"),
        ConversationTurn(role: "assistant", text: "Gases like CO2 trap outgoing heat [1]."),
    ])

    /// Records every stage's (system, user) and answers with `replies`.
    final class Recorder: StageGenerator, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [(system: String, user: String)] = []
        private let replies: @Sendable (String, String) -> String
        init(_ replies: @escaping @Sendable (String, String) -> String) { self.replies = replies }
        var calls: [(system: String, user: String)] { lock.withLock { recorded } }
        func generate(system: String, user: String, nPredict: Int, temperature: Float, timeoutMs: Int64?, onToken: (@Sendable (String) -> Void)?) async throws -> GenResult {
            lock.withLock { recorded.append((system, user)) }
            return GenResult(text: replies(system, user))
        }
    }

    @Test func aFollowUpIsRewrittenFromTheLastExchangeThenSplitAndSynthesizedWithIt() async throws {
        let gen = Recorder { system, _ in
            if system.hasPrefix("You rewrite") { return "What is the conclusion about how the greenhouse effect warms the planet?" }
            if system.hasPrefix("You plan") { return "I'm sorry, but I can't help with that.\nWhat gases drive the greenhouse effect?\nHow much has the planet warmed?" }
            return "ok"
        }
        let searched = Log<String>()
        let r = try await DeepResearch(generator: gen, retrieve: { q, _ in searched.add(q); return [] }, timeoutFor: { _ in nil })
            .run("conclusion", systemPrompt: nil, history: history, maxTokens: 256)
        #expect(gen.calls[0].user.contains("Previous question: How does the greenhouse effect"))
        #expect(gen.calls[1].user.contains("Question: What is the conclusion about how the greenhouse effect"))
        #expect(r.subQuestions == ["What gases drive the greenhouse effect?", "How much has the planet warmed?"])
        #expect(searched.all == r.subQuestions)
        let synthesis = gen.calls.last!.user
        #expect(synthesis.contains("Previous answer: Gases like CO2 trap outgoing heat [1]."))
        #expect(synthesis.contains("Follow-up as asked: conclusion"))
    }

    @Test func aQuestionThatNamesItsOwnSubjectIsNotRewritten() async throws {
        let gen = Recorder { _, _ in "ok" }
        _ = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("How do Australian bushfires start?", systemPrompt: nil, history: history, maxTokens: 256)
        #expect(gen.calls.allSatisfy { !$0.system.hasPrefix("You rewrite") })
        #expect(DeepResearch.lastExchange("How do Australian bushfires start?", history) == nil)
        #expect(DeepResearch.lastExchange("conclusion", nil) == nil)
    }

    @Test func aRefusedRewriteKeepsTheFollowUpAsAsked() async throws {
        let gen = Recorder { system, _ in system.hasPrefix("You rewrite") ? "Sorry, I cannot do that." : "ok" }
        _ = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("continue", systemPrompt: nil, history: history, maxTokens: 256)
        #expect(gen.calls[1].user.contains("Question: continue"))
    }

    @Test func stopDuringTheRewriteEndsTheAnswerBeforeTheSplit() async throws {
        let stop = LockedBox(false)
        let gen = Recorder { system, _ in
            if system.hasPrefix("You rewrite") { stop.value = true; return "What is the conclusion about the greenhouse effect?" }
            return "ok"
        }
        let r = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("conclusion", systemPrompt: nil, history: history, maxTokens: 256, shouldStop: { stop.value })
        #expect(gen.calls.count == 1)
        #expect(r.subQuestions.isEmpty)
    }

    @Test func theWriteUpGetsItsOwnTimeLimit() async throws {
        let limits = Log<Int64?>()
        let gen = ClosureStageGenerator { system, _, _, _, timeoutMs, _ in
            limits.add(timeoutMs)
            return GenResult(text: system.hasPrefix("You plan") ? "Sub one about gases?\nSub two about heat?" : "ok")
        }
        _ = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in 1000 }, writeUpTimeoutFor: { _ in nil })
            .run("How does the greenhouse effect warm the planet?", systemPrompt: nil, history: nil, maxTokens: 256)
        #expect(limits.all == [1000, 1000, 1000, nil])
    }

    @Test func aStoppedQuestionWithNoAnswerIsSkippedForTheOneBeforeIt() {
        let h = ConversationHistory(turns: history.turns + [ConversationTurn(role: "user", text: "conclusion")])
        #expect(DeepResearch.lastExchange("continue", h)?.question == "How does the greenhouse effect warm the planet?")
    }

    @Test func aSecondContinueBuildsOnTheFirstOnesAnswer() {
        let h = ConversationHistory(turns: history.turns + [ConversationTurn(role: "user", text: "continue"), ConversationTurn(role: "assistant", text: "More on trapped heat [2].")])
        #expect(DeepResearch.lastExchange("continue", h)?.question == "continue")
        #expect(DeepResearch.lastExchange("continue", h)?.answer == "More on trapped heat [2].")
    }

    @Test func refusalLinesAreNotSubQuestions() {
        #expect(DeepResearch.parseSubQuestions("Desculpe, não posso ajudar com isso.\nI cannot answer that question", "q") == ["q"])
    }
}
