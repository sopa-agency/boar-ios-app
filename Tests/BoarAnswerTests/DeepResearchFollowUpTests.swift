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
            .run("and its conclusion?", systemPrompt: nil, history: history, maxTokens: 256)
        #expect(gen.calls[0].user.contains("Previous question: How does the greenhouse effect"))
        #expect(gen.calls[1].user.contains("Question: What is the conclusion about how the greenhouse effect"))
        #expect(r.subQuestions == ["What gases drive the greenhouse effect?", "How much has the planet warmed?"])
        #expect(searched.all == r.subQuestions)
        let synthesis = gen.calls.last!.user
        #expect(synthesis.contains("Previous answer: Gases like CO2 trap outgoing heat [1]."))
        #expect(synthesis.contains("Follow-up as asked: and its conclusion?"))
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
            .run("and the oceans?", systemPrompt: nil, history: history, maxTokens: 256)
        #expect(gen.calls[1].user.contains("Question: and the oceans?"))
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

    @Test func theReceiptGetsTheWriteUpsNumbers() async throws {
        // Deep Research answers had an empty receipt: no context, no engine speed (X6, Oct 13).
        let n = LockedBox(0)
        let gen = ClosureStageGenerator { system, _, _, _, _, _ in
            let i = n.withValue { v -> Int in defer { v += 1 }; return v }
            let m = GenerationMetrics(promptTokens: 100 + i, promptTokensDecoded: 100 + i, generatedTokens: 10, ttftMs: 1, prefillMs: 1, decodeMs: 1,
                prefillTokPerSec: 1, decodeTokPerSec: 9.5, totalMs: 2, stopReason: "eos")
            return GenResult(text: system.hasPrefix("You plan") ? "Sub one about gases?\nSub two about heat?" : "ok", metrics: m)
        }
        let r = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("How does the greenhouse effect warm the planet?", systemPrompt: nil, history: nil, maxTokens: 256)
        #expect(r.metrics?.promptTokens == 103)
        let meta = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("summary", systemPrompt: nil, history: history, maxTokens: 256, previousAnswer: "Gases trap heat [1].")
        #expect(meta.metrics?.promptTokens == 104)
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

    @Test func metaFollowUpsAreRecognizedQuestionsWithASubjectOfTheirOwnAreNot() {
        for q in ["summary", "Conclusion", "TL;DR", "tldr", "continue", "go on", "tell me more", "a brief summary please",
                  "a executive summary please", "sum it up", "resuma", "um resumo por favor", "continua"] {
            #expect(DeepResearch.isMetaFollowUp(q), "\(q)")
        }
        for q in ["summary of the causes of war", "What is the conclusion of the Treaty of Versailles?", "continue the history of Rome",
                  "How does the greenhouse effect warm the planet?", "more about volcanoes", ""] {
            #expect(!DeepResearch.isMetaFollowUp(q), "\(q)")
        }
    }

    @Test func aMetaFollowUpIsWrittenFromTheFullPreviousAnswerWithNoSplittingOrSearch() async throws {
        let gen = Recorder { _, _ in "In short: CO2 traps heat [1]." }
        let searched = Log<String>()
        let full = "Gases like CO2 trap outgoing heat [1]. Oceans absorb most of the excess [2]."
        let r = try await DeepResearch(generator: gen, retrieve: { q, _ in searched.add(q); return [] }, timeoutFor: { _ in nil })
            .run("TL;DR", systemPrompt: nil, history: history, maxTokens: 256, previousAnswer: full)
        #expect(gen.calls.count == 1)
        #expect(searched.all.isEmpty)
        #expect(r.fromPreviousAnswer)
        #expect(r.subQuestions.isEmpty)
        #expect(r.answer == "In short: CO2 traps heat [1].")
        let (system, user) = gen.calls[0]
        #expect(system.contains("keep its source numbers exactly as written"))
        #expect(user.contains("Previous question: How does the greenhouse effect warm the planet?"))
        #expect(user.contains("Oceans absorb most of the excess [2]."))
        #expect(user.hasSuffix("Follow-up: TL;DR"))
    }

    @Test func withNoPreviousAnswerAMetaFollowUpResearchesAsUsual() async throws {
        let gen = Recorder { _, _ in "ok" }
        let r = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("summary", systemPrompt: nil, history: nil, maxTokens: 256)
        #expect(!r.fromPreviousAnswer)
        #expect(gen.calls.first!.system.hasPrefix("You plan"))
    }

    @Test func refusalLinesAreNotSubQuestions() {
        #expect(DeepResearch.parseSubQuestions("Desculpe, não posso ajudar com isso.\nI cannot answer that question", "q") == ["q"])
    }

    @Test func aConversationRecapIsToldApartFromASummaryOfASubject() {
        for q in ["Summarize our conversation in 3 bullet points", "recap what we discussed", "resuma a nossa conversa", "TL;DR of this chat"] {
            #expect(DeepResearch.isConversationRecap(q), "\(q)")
        }
        for q in ["Summarize the causes of the French Revolution", "How do vaccines work?", "summary",
                  "Summarize the conversation between Kennedy and Khrushchev", "Summarize a chat about Ubuntu"] {
            #expect(!DeepResearch.isConversationRecap(q), "\(q)")
        }
    }

    @Test func aWriteUpOfThisChatIsARecapAWriteUpOfASubjectIsNot() {
        for q in ["write an artifact about all our conversation", "Make a report of what we discussed", "create notes from this chat",
                  "Give me a short document covering everything we talked about so far", "faça um relatório da nossa conversa",
                  "escreva um documento sobre o que conversamos"] {
            #expect(DeepResearch.isConversationRecap(q), "\(q)")
        }
        for q in ["Write a report about the French Revolution", "make notes on photosynthesis",
                  "Write a report about the conversation between Kennedy and Khrushchev", "escreva um texto sobre a Revolução Francesa", "write",
                  "Write a report on Bitcoin's history so far", "Make notes on all of this year's Ethereum upgrades",
                  // The document must follow the verb on the same line, as the single regex read it.
                  "write\na report of our conversation", "a report: write our conversation"] {
            #expect(!DeepResearch.isConversationRecap(q), "\(q)")
        }
        // Linear: 20,000 characters of "write," took 2.7 s with the single regex.
        let t = monotonicMillis()
        #expect(!DeepResearch.isConversationRecap(String(repeating: "write,", count: 3_333) + " our chat"))
        #expect(monotonicMillis() - t < 300)
    }

    @Test func plainChatWritesASummaryFromTheLastAnswerNotAContinue() {
        #expect(DeepResearch.isSummaryFollowUp("TL;DR"))
        #expect(DeepResearch.isSummaryFollowUp("a brief summary please"))
        #expect(DeepResearch.isSummaryFollowUp("conclusion"))
        #expect(!DeepResearch.isSummaryFollowUp("continue"))
        #expect(!DeepResearch.isSummaryFollowUp("tell me more"))
        #expect(!DeepResearch.isSummaryFollowUp("How do vaccines work?"))
    }

    @Test func aRecapDropsTheOldCitationNumbersAndKeepsTheEarlierSummaryPast12Exchanges() async throws {
        let gen = Recorder { _, _ in "ok" }
        let conversation = (1...14).map { DeepResearch.Exchange(question: "Question \($0)?", answer: "Answer \($0) [2].") }
        _ = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("recap our chat", systemPrompt: nil, history: ConversationHistory(summary: "Talked about tides [1]."), maxTokens: 256, conversation: conversation)
        #expect(gen.calls.count == 1)
        let user = gen.calls[0].user
        #expect(user.contains("Summary of the earlier conversation:\nTalked about tides."))
        #expect(!user.contains("Question 2?"))
        #expect(user.contains("1. Question: Question 3?\nAnswer: Answer 3."))
        #expect(!user.contains("[2]"))
    }

    @Test func aConversationRecapIsWrittenFromEveryExchangeWithoutASearch() async throws {
        // It covered only the last two topics of nine: history keeps the last three exchanges (X6, Oct 16).
        let gen = Recorder { _, _ in "- seasons\n- the Moon\n- vaccines" }
        let searched = Log<String>()
        let conversation = [
            DeepResearch.Exchange(question: "What causes the seasons on Earth?", answer: "The axial tilt of about 23.4 degrees."),
            DeepResearch.Exchange(question: "How far away is the Moon?", answer: "About 384,000 km."),
            DeepResearch.Exchange(question: "How do vaccines work?", answer: "They train the immune system. " + String(repeating: "x", count: 2000)),
        ]
        let r = try await DeepResearch(generator: gen, retrieve: { q, _ in searched.add(q); return [] }, timeoutFor: { _ in nil })
            .run("Summarize our conversation in 3 bullet points", systemPrompt: nil, history: history, maxTokens: 256, conversation: conversation)
        #expect(gen.calls.count == 1)
        #expect(searched.all.isEmpty)
        let user = gen.calls[0].user
        #expect(user.contains("1. Question: What causes the seasons on Earth?"))
        #expect(user.contains("3. Question: How do vaccines work?"))
        #expect(user.contains("Request: Summarize our conversation in 3 bullet points"))
        #expect(!user.contains(String(repeating: "x", count: DeepResearch.recapAnswerChars + 1)))
        #expect(r.answer == "- seasons\n- the Moon\n- vaccines")
        #expect(!r.fromPreviousAnswer)
    }

    @Test func aRecapLeavesOutEarlierRecapsAndSummaries() async throws {
        let gen = Recorder { _, _ in "ok" }
        let conversation = [
            DeepResearch.Exchange(question: "What causes the seasons on Earth?", answer: "The axial tilt."),
            DeepResearch.Exchange(question: "Summarize our conversation in 3 bullet points", answer: "- the axial tilt"),
            DeepResearch.Exchange(question: "TL;DR", answer: "Tilt."),
            DeepResearch.Exchange(question: "How far away is the Moon?", answer: "About 384,000 km."),
        ]
        _ = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("Summarize our conversation in 3 bullet points", systemPrompt: nil, history: history, maxTokens: 256, conversation: conversation)
        #expect(gen.calls.count == 1)
        let user = gen.calls[0].user
        #expect(user.contains("1. Question: What causes the seasons on Earth?"))
        #expect(user.contains("2. Question: How far away is the Moon?"))
        #expect(!user.contains("TL;DR"))
        #expect(!user.contains("- the axial tilt"))
    }

    @Test func withoutEarlierExchangesARecapRequestIsResearchedAsAsked() async throws {
        let gen = Recorder { _, _ in "ok" }
        _ = try await DeepResearch(generator: gen, retrieve: { _, _ in [] }, timeoutFor: { _ in nil })
            .run("Summarize our conversation", systemPrompt: nil, history: nil, maxTokens: 256)
        #expect(gen.calls.contains { $0.system.hasPrefix("You plan") })
    }
}
