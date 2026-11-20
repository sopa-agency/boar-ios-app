import BoarCore
import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// Boar Staged answers: the steps' order, Stop between them, the research step and the number check (android StagedAnswerTest).
struct StagedAnswerTests {
    /// A scripted model: reply n answers the n-th generation. `onCall` runs when a generation starts (a Stop pressed in it).
    private final class Model: TextModelSession, @unchecked Sendable {
        let info = ModelInfo(name: "fake.gguf", backend: "test")
        let capabilities: ModelCapabilities
        private let replies: [String]
        private let onCall: @Sendable (Int) -> Void
        let requests = Log<GenerationRequest>()

        init(_ replies: String..., template: Bool = false, onCall: @escaping @Sendable (Int) -> Void = { _ in }) {
            capabilities = ModelCapabilities(hasChatTemplate: template, acceptsRawPrompt: true)
            self.replies = replies; self.onCall = onCall
        }

        /// The raw prompts asked, in order.
        var prompts: [String] { requests.all.map { if case .prompt(let p) = $0.input { p } else { "" } } }

        func cancel() {}
        func close() async {}
        func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
            requests.add(request)
            let n = requests.all.count - 1
            onCall(n)
            let reply = replies[n]
            return AsyncThrowingStream { c in
                c.yield(.piece(reply))
                c.yield(.done(GenerationMetrics(generatedTokens: 1, stopReason: "eos")))
                c.finish()
            }
        }
    }

    private static let volcano = Chunk(chunkId: "v1", docId: "volcano", title: "Volcano", body: "A volcano forms where magma rises through the crust. Mount Etna is 3,357 m high.")
    private static let plate = Chunk(chunkId: "p1", docId: "plates", title: "Plate tectonics", body: "Most volcanoes form at plate boundaries where magma rises.")
    private static let q = "How do volcanoes form?"

    private func req(details: String? = "Be thorough.") -> StagedRequest {
        StagedRequest(query: Self.q, systemPrompt: "You are BOAR.", introReminder: "Keep it short.", detailsReminder: details, maxTokens: 512)
    }

    private func staged(_ found: @escaping @Sendable (String) -> [Chunk]) -> StagedAnswer {
        StagedAnswer(retrieve: { s, _ in found(s) }, classify: { _ in "explanation" }, retrievalIrrelevant: { _ in false })
    }

    private func collect(_ stream: AsyncThrowingStream<StagedEvent, Error>, onEvent: (StagedEvent) -> Void = { _ in }) async throws -> [StagedEvent] {
        var out: [StagedEvent] = []
        for try await e in stream { onEvent(e); out.append(e) }
        return out
    }

    private func steps(_ events: [StagedEvent]) -> [StagedStep] { events.compactMap { if case .step(let s) = $0 { s } else { nil } } }
    private func done(_ events: [StagedEvent]) throws -> StagedDone {
        let all = events.compactMap { if case .done(let d) = $0 { d } else { nil } }
        try #require(all.count == 1)
        return all[0]
    }

    @Test func theCardsComeBeforeTheModelLoads() async throws {
        let model = Model("Magma rises [1].", "Etna is 3,357 m [1].")
        let cards = LockedBox(false)
        let loadedAfterCards = LockedBox(false)
        // The stream is buffered, so the load waits (up to 2 s) for the consumer to have the cards in hand.
        let events = try await collect(staged { _ in [Self.volcano] }.answer(req(), load: {
            for _ in 0..<200 where !cards.value { try? await Task.sleep(for: .milliseconds(10)) }
            loadedAfterCards.value = cards.value
            return model
        }, shouldStop: { false })) { if case .cards = $0 { cards.value = true } }
        #expect(loadedAfterCards.value)
        #expect(steps(events) == [.sources, .intro, .research, .details, .check])
        let d = try done(events)
        #expect(d.text == "Magma rises [1].\n\nEtna is 3,357 m [1].")
        #expect(d.unsupported == [])
        // The details go on from the intro, the model's own turn.
        #expect(model.prompts[1].contains("Magma rises [1]."))
        #expect(model.prompts[1].contains(StagedAnswer.detailsAsk))
    }

    @Test func theResearchStepAddsPassagesFromArticlesNotYetReadNumberedAfterTheFirst() async throws {
        let model = Model("Magma rises at plate boundaries.", "More [3].")
        let events = try await collect(staged { $0 == Self.q ? [Self.volcano] : [Self.volcano, Self.plate] }.answer(req(), load: { model }, shouldStop: { false }))
        #expect(try done(events).sources.map(\.docId) == ["volcano", "plates"])
        #expect(model.prompts[1].contains("[2] Plate tectonics"))
    }

    /// Kotlin sets the flag from the collector after the intro's piece; the stream here is buffered, so the Stop is pressed as
    /// the intro starts (same order: after the intro was asked, before the details).
    @Test func stopAfterTheIntroKeepsTheIntroAndSkipsTheDetails() async throws {
        let stop = LockedBox(false)
        let model = Model("Magma rises [1].", "never") { _ in stop.value = true }
        let d = try await done(collect(staged { _ in [Self.volcano] }.answer(req(), load: { model }, shouldStop: { stop.value })))
        #expect(d.text == "Magma rises [1].")
        #expect(d.stopped)
        #expect(model.prompts.count == 1)
    }

    @Test func aHealthQuestionKeptShortIsTheIntroAlone() async throws {
        let model = Model("Cool the burn under running water [1].")
        let d = try await done(collect(staged { _ in [Self.volcano] }.answer(req(details: nil), load: { model }, shouldStop: { false })))
        #expect(model.prompts.count == 1)
        #expect(d.times.detailsFirstMs == nil)
    }

    @Test func noModelLeavesTheCards() async throws {
        let d = try await done(collect(staged { _ in [Self.volcano] }.answer(req(), load: { nil }, shouldStop: { false })))
        #expect(d.noModel)
        #expect(d.sources.count == 1)
        #expect(!d.keyFacts.isEmpty)
    }

    @Test func keyFactsAreTheBestAnsweringSentenceOfEachSource() {
        let facts = StagedAnswer.keyFacts(Self.q, [Self.volcano, Self.plate])
        #expect(facts.count == 2)
        #expect(facts.allSatisfy { $0.sentence.lowercased().contains("magma") })
    }

    @Test func numbersNotInAnySourceAreFlaggedCitationsAndSmallCountsAreNot() {
        let evidence = ["Mount Etna is 3,357 m high."]
        #expect(StagedAnswer.unsupportedNumbers("Etna is 3357 m [12], not 4,000 m. There are 3 kinds.\n1. One", evidence) == ["4,000"])
        #expect(StagedAnswer.unsupportedNumbers("Etna is 3,357 m high [1].", evidence) == [])
    }

    @Test func aSourceOutsideTheQuotesGetsItsBestSentenceOrItsFirst() {
        #expect(StagedAnswer.factOf(Self.q, Self.volcano) == "A volcano forms where magma rises through the crust.")
        let off = Chunk(chunkId: "o1", docId: "football", title: "Football", body: "The 1950 World Cup was held in Brazil. Uruguay won it.")
        #expect(StagedAnswer.factOf(Self.q, off) == "The 1950 World Cup was held in Brazil.")
    }

    @Test func aFigureWithAScaleWordIsBackedByTheSourcesFullNumberAtTheDigitsStated() {
        let facts = ["Russia: population 146,119,928 (2025); area 17,075,400 km². Brazil: population 214,211,951 (2026)."]
        // The F3, 15 Nov: "146 million" was flagged against 146,119,928.
        #expect(StagedAnswer.unsupportedNumbers("Russia has about 146 million people [1].", facts) == [])
        #expect(StagedAnswer.unsupportedNumbers("Russia covers 17.1 million km² and Brazil has 214 million people.", facts) == [])
        // Portuguese, with the source written either way.
        #expect(StagedAnswer.unsupportedNumbers("A Rússia tem cerca de 146 milhões de habitantes e 17,1 milhões de km².", facts) == [])
        #expect(StagedAnswer.unsupportedNumbers("O Brasil tem 214 milhões de habitantes.", ["Brasil: 214.211.951 habitantes."]) == [])
        // Wrong at the digits stated is still flagged; a bare number keeps the old rule.
        #expect(StagedAnswer.unsupportedNumbers("Russia has about 150 million people.", facts) == ["150"])
        #expect(StagedAnswer.unsupportedNumbers("Russia covers 17.2 million km².", facts) == ["17.2"])
        #expect(StagedAnswer.unsupportedNumbers("Russia has 146 regions.", facts) == ["146"])
    }

    @Test func theScaleWordSaysWhichMarkIsDecimal() {
        let billion = ["The fund holds 1,234,000,000 dollars."]
        // "1.234 million" is 1,234,000: not backed by 1,234,000,000 (was a 1000x false accept).
        #expect(StagedAnswer.unsupportedNumbers("It holds 1.234 million dollars.", billion) == ["1.234"])
        #expect(StagedAnswer.unsupportedNumbers("Tem 1,234 milhões de dólares.", billion) == ["1,234"])
        // The right readings still pass.
        #expect(StagedAnswer.unsupportedNumbers("It holds 1,234 million dollars.", billion) == [])
        #expect(StagedAnswer.unsupportedNumbers("It holds 1.234 billion dollars.", billion) == [])
        #expect(StagedAnswer.unsupportedNumbers("Tem 1,234 bilhão de dólares.", billion) == [])
    }

    // MARK: Not in Kotlin's test (the Swift port's own checks)

    /// android 10a42933: a model that reasons first spends the intro's 160 tokens inside <think>.
    @Test func aReasoningOnlyIntroRestartsAsTheWholeAnswerWithNoDetails() async throws {
        let model = Model("<think>Let me think about magma and crust", "Magma rises [1].")
        let events = try await collect(staged { _ in [Self.volcano] }.answer(req(), load: { model }, shouldStop: { false }))
        #expect(events.contains { if case .restart = $0 { true } else { false } })
        #expect(!steps(events).contains(.details))
        let d = try done(events)
        #expect(d.text == "Magma rises [1].")
        // The second run has the details' style line and the full budget; the first the intro's cap.
        #expect(model.requests.all.map(\.sampling.nPredict) == [StagedAnswer.introTokens, 512])
        #expect(model.prompts[1].contains("Be thorough."))
    }

    /// android b232d3c8: the details ask is English, so the answer's language comes from the question.
    @Test func theDetailsStepAsksInTheQuestionsLanguage() async throws {
        let model = Model("A lava sobe [1].", "Mais [1].")
        let r = StagedRequest(query: "Como se formam os vulcões? Explique com detalhes, por favor.", systemPrompt: nil, introReminder: "Curto.", detailsReminder: "Longo.", maxTokens: 512)
        _ = try await collect(staged { _ in [Self.volcano] }.answer(r, load: { model }, shouldStop: { false }))
        let line = try #require(AnswerLanguage.line(.pt, withSources: true))
        #expect(AnswerLanguage.of(r.query, earlier: []) == .pt)
        #expect(model.prompts[1].contains(line))
    }

    @Test func aModelWithATemplateGetsMessagesAndNoStopWords() async throws {
        let model = Model("Magma rises [1].", "More [1].", template: true)
        _ = try await collect(staged { _ in [Self.volcano] }.answer(req(), load: { model }, shouldStop: { false }))
        let r = model.requests.all
        #expect(r.count == 2)
        guard case .messages(let m) = r[1].input else { Issue.record("expected messages"); return }
        #expect(m.map(\.role) == ["system", "user", "assistant", "user"])
        #expect(m.last?.content.hasPrefix(StagedAnswer.detailsAsk) == true)
        #expect(r.allSatisfy { $0.sampling.stops.isEmpty && $0.sampling.temperature == 0.7 })
    }

    @Test func retrievalFreeTasksSkipTheCardsAndTheCheck() async throws {
        let model = Model("Hello there.", "More.")
        let s = StagedAnswer(retrieve: { _, _ in Issue.record("searched"); return [] }, classify: { _ in "greeting" }, retrievalIrrelevant: { $0 == "greeting" })
        let events = try await collect(s.answer(req(), load: { model }, shouldStop: { false }))
        #expect(steps(events) == [.intro, .details])
        let d = try done(events)
        #expect(d.sources.isEmpty && d.unsupported == nil && d.retrievalMs == nil && d.times.sourcesMs == nil)
    }

    @Test func theJoinKeepsRunningTextAndTheTimesMapOnlyWhatRan() {
        #expect(StagedAnswer.join("  one ", "") == "one")
        #expect(StagedAnswer.join("one", " two\n") == "one\n\ntwo")
        #expect(StageTimes(sourcesMs: 1, totalMs: 9).toMap() == ["sources": 1, "total": 9])
        #expect(StagedShown.any(quotes: 0, more: 0, added: 0, stepLine: false) == false)
        #expect(StagedShown.any(quotes: 0, more: 0, added: 1, stepLine: false))
    }

    // Left for the UI PR (they read Android's Compose sources): `the chat keeps the quotes open, shows +N sources and hides its
    // own list for a lab that owns them`, `a tall answer keeps its taps, the bubble's shape is drawn and never clipped`.
}
