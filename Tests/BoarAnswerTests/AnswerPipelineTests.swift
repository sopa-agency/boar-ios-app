import BoarCore
import BoarRAG
import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// A scripted model behind the seam: streams `pieces`, honours cancel() and records what it was asked.
final class FakeSession: TextModelSession, @unchecked Sendable {
    let info = ModelInfo(name: "fake.gguf", backend: "test")
    let capabilities: ModelCapabilities
    private let pieces: [String]
    private let delay: Duration
    let requests = Log<GenerationRequest>()
    private let cancelled = LockedBox(false)
    /// The consumer left before the stream finished on its own.
    let abandoned = LockedBox(false)

    init(template: Bool = true, pieces: [String], delay: Duration = .zero) {
        capabilities = ModelCapabilities(hasChatTemplate: template, acceptsRawPrompt: true)
        self.pieces = pieces; self.delay = delay
    }

    func cancel() { cancelled.value = true }
    func close() async {}

    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        requests.add(request)
        cancelled.value = false
        let finished = LockedBox(false)
        return AsyncThrowingStream { c in
            let task = Task {
                var generated = 0
                for p in pieces {
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    if cancelled.value || Task.isCancelled { break }
                    c.yield(.piece(p)); generated += 1
                }
                let reason = cancelled.value ? "cancelled" : "eos"
                if !Task.isCancelled {
                    c.yield(.done(GenerationMetrics(generatedTokens: generated, stopReason: reason)))
                    finished.value = true
                    c.finish()
                }
            }
            c.onTermination = { [abandoned] _ in
                task.cancel()
                if !finished.value { abandoned.value = true }
            }
        }
    }
}

struct AnswerPipelineTests {
    private static let source = Chunk(chunkId: "seed:1", docId: "d1", title: "Canberra", body: "Canberra is the capital of Australia. It lies inland.")

    private func pipeline(_ session: FakeSession, retrieved: Log<String>) -> AnswerPipeline {
        AnswerPipeline(
            session: session, retrieve: { q, _ in retrieved.add(q); return [Self.source] },
            classify: { Classify.classifyTask($0).value },
            retrievalIrrelevant: { name in TaskType(rawValue: name).map(Classify.isRetrievalIrrelevant) ?? false }
        )
    }

    private func collect(_ stream: AsyncThrowingStream<AnswerEvent, Error>) async throws -> [AnswerEvent] {
        var out: [AnswerEvent] = []
        for try await e in stream { out.append(e) }
        return out
    }

    private func label(_ e: AnswerEvent) -> String {
        switch e {
        case .stage(let s): "stage:\(s.rawValue)"
        case .sources(let c, _, _, _): "sources:\(c.count)"
        case .piece(let p): "piece:\(p)"
        case .done: "done"
        }
    }

    @Test func aTemplateModelGetsMessagesAndTheSourcesComeBeforeTheText() async throws {
        let session = FakeSession(pieces: ["Canberra", " [1]."])
        let retrieved = Log<String>()
        let events = try await collect(pipeline(session, retrieved: retrieved).answer(
            AnswerRequest(query: "What is the capital of Australia?", systemPrompt: "Be brief.", styleReminder: "Short.", maxTokens: 200, enableThinking: true)
        ))
        #expect(events.map(label) == ["stage:retrieving", "sources:1", "stage:thinking", "stage:generating", "piece:Canberra", "piece: [1].", "done"])
        guard case .done(let done) = events.last else { Issue.record("no done"); return }
        #expect(done.text == "Canberra [1].")
        #expect(done.promptFormat == "chat-template" && done.retrieved && done.sources.count == 1)
        #expect(done.metrics?.generatedTokens == 2)
        let request = try #require(session.requests.all.first)
        guard case .messages(let messages) = request.input else { Issue.record("expected messages"); return }
        #expect(messages.first?.role == .system && messages.last?.role == .user)
        #expect(messages.last?.content.hasSuffix("(Response style: Short.)") == true)
        #expect(request.sampling.nPredict == 200 && request.sampling.stops.isEmpty && request.enableThinking)
        #expect(retrieved.all == ["What is the capital of Australia?"])
    }

    @Test func aModelWithoutATemplateGetsAPlainPromptWithStopWords() async throws {
        let session = FakeSession(template: false, pieces: ["ok"])
        let events = try await collect(pipeline(session, retrieved: Log<String>()).answer(AnswerRequest(query: "What is the capital of Australia?", systemPrompt: nil)))
        guard case .done(let done) = events.last else { Issue.record("no done"); return }
        #expect(done.promptFormat == "plain")
        let request = try #require(session.requests.all.first)
        guard case .prompt(let prompt) = request.input else { Issue.record("expected a prompt"); return }
        #expect(prompt.hasSuffix("Answer:") && prompt.contains("Question: What is the capital of Australia?"))
        #expect(request.sampling.stops == AnswerStopSequences.plain)
    }

    @Test func aGreetingSkipsRetrieval() async throws {
        let session = FakeSession(pieces: ["Hi!"])
        let retrieved = Log<String>()
        let events = try await collect(pipeline(session, retrieved: retrieved).answer(AnswerRequest(query: "hey, what's up?", systemPrompt: nil)))
        #expect(events.map(label) == ["stage:thinking", "stage:generating", "piece:Hi!", "done"])
        #expect(retrieved.all.isEmpty)
        guard case .done(let done) = events.last else { Issue.record("no done"); return }
        #expect(!done.retrieved && done.sources.isEmpty && done.retrievalMs == nil)
    }

    @Test func aFollowUpIsSearchedWithThePreviousQuestion() async throws {
        let session = FakeSession(pieces: ["He wrote it."])
        let retrieved = Log<String>()
        let history = ConversationHistory(turns: [ConversationTurn(role: "user", text: "Who was Charles Darwin?"), ConversationTurn(role: "assistant", text: "A naturalist.")])
        _ = try await collect(pipeline(session, retrieved: retrieved).answer(AnswerRequest(query: "What did he publish?", systemPrompt: nil, history: history)))
        #expect(retrieved.all == ["Who was Charles Darwin? What did he publish?"])
    }

    @Test func aRetrievalFailureIsThrownFromTheStream() async {
        struct Boom: Error {}
        let session = FakeSession(pieces: ["x"])
        let p = AnswerPipeline(session: session, retrieve: { _, _ in throw Boom() }, classify: { _ in "lookup" }, retrievalIrrelevant: { _ in false })
        await #expect(throws: Boom.self) { _ = try await collect(p.answer(AnswerRequest(query: "q", systemPrompt: nil))) }
        #expect(session.requests.all.isEmpty)
    }

    @Test func stopKeepsTheTextWrittenSoFar() async throws {
        let session = FakeSession(pieces: Array(repeating: "w ", count: 50), delay: .milliseconds(20))
        let p = pipeline(session, retrieved: Log<String>())
        var text = ""
        var done: AnswerResult?
        for try await e in p.answer(AnswerRequest(query: "hey there", systemPrompt: nil)) {
            switch e {
            case .piece(let s): text += s; if text.count >= 6 { p.cancel() }
            case .done(let d): done = d
            default: break
            }
        }
        let result = try #require(done)
        #expect(result.metrics?.stopReason == "cancelled")
        #expect(result.text == text && text.count < 100)
    }

    @Test func droppingTheStreamStopsTheGeneration() async throws {
        let session = FakeSession(pieces: Array(repeating: "w ", count: 500), delay: .milliseconds(10))
        let p = pipeline(session, retrieved: Log<String>())
        for try await e in p.answer(AnswerRequest(query: "hey there", systemPrompt: nil)) {
            if case .piece = e { break }
        }
        for _ in 0..<100 where !session.abandoned.value { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.abandoned.value)
    }
}

struct SessionEngineTests {
    @Test func theTimeLimitCancelsTheGenerationAndKeepsTheText() async throws {
        let session = FakeSession(pieces: Array(repeating: "w ", count: 400), delay: .milliseconds(10))
        let engine = SessionEngine(session)
        let r = try await engine.generate(system: "S", user: "U", nPredict: 64, temperature: 0.3, timeoutMs: 150, onToken: nil)
        #expect(r.timedOut)
        #expect(!r.text.isEmpty && r.text.count < 800)
        #expect(r.metrics?.stopReason == "cancelled")
    }

    @Test func aTemplateModelGetsSystemAndUserMessagesAndAPlainOneGetsTheTaskPrompt() async throws {
        let withTemplate = FakeSession(pieces: ["a"])
        _ = try await SessionEngine(withTemplate).generate(system: "SYS", user: "USR", nPredict: 16, temperature: 0.3, timeoutMs: nil, onToken: nil)
        guard case .messages(let m) = withTemplate.requests.all[0].input else { Issue.record("expected messages"); return }
        #expect(m.map(\.content) == ["SYS", "USR"])
        #expect(withTemplate.requests.all[0].sampling.nPredict == 16 && withTemplate.requests.all[0].sampling.stops.isEmpty)

        let plain = FakeSession(template: false, pieces: ["a"])
        let streamed = Log<String>()
        _ = try await SessionEngine(plain).generate(system: "SYS", user: "USR", nPredict: 16, temperature: 0.3, timeoutMs: nil, onToken: { streamed.add($0) })
        guard case .prompt(let p) = plain.requests.all[0].input else { Issue.record("expected a prompt"); return }
        #expect(p == "SYS\n\nUSR\n\nAnswer:")
        #expect(plain.requests.all[0].sampling.stops == AnswerStopSequences.plain)
        #expect(streamed.all == ["a"])
    }

    @Test func theExecutorRunsOverASessionEngine() async throws {
        struct Host: ModelHost {
            let engine: SessionEngine
            func residentFilename() async -> String? { "models/m1.gguf" }
            func filenameOf(_ id: String) async -> String? { "models/\(id).gguf" }
            func load(_ id: String) async throws -> (any StepEngine)? { engine }
        }
        let session = FakeSession(pieces: ["SUPPORTED", " fine."])
        let plan = Router.RoutingPlan(
            steps: [
                Router.RoutingStep(id: "r", type: .retrieve, required: false),
                Router.RoutingStep(id: "g", type: .generate, modelId: "m1", required: true, maxTokens: 64),
                Router.RoutingStep(id: "v", type: .verify, modelId: "m1", required: false, maxTokens: 20),
            ],
            selectedModelIds: ["m1"], estimatedCost: Router.CostEstimate(modelSwitches: 0), fallbackPolicy: .useDefault, reasonCodes: []
        )
        let r = try await PlanExecutor(
            host: Host(engine: SessionEngine(session)),
            retrieve: { _, _ in [Chunk(chunkId: "c1", docId: "d", title: "Canberra", body: "Canberra is the capital of Australia.")] },
            classify: { _ in "lookup" }, timeoutFor: { _ in nil }
        ).execute(plan: plan, input: PipelineInput(query: "What is the capital of Australia?"))
        #expect(r.stepsExecuted == 3 && r.modelResidency == "resident")
        #expect(r.verification.status == "passed")
        #expect(session.requests.all.count == 2 && session.requests.all[1].sampling.temperature == 0.2)
        #expect(r.ttftMs != nil && r.promptFormat == "chat-template")
    }
}
