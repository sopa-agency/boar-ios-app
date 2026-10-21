import BoarCore
import BoarRAG
import BoarRouting
import Foundation

/// One question for the default answer path.
public struct AnswerRequest: Sendable {
    public var query: String
    public var systemPrompt: String?
    public var styleReminder: String?
    public var maxTokens: Int
    public var history: ConversationHistory?
    /// Advanced tweak; off by default (`EngineTweaks.thinking`).
    public var enableThinking: Bool

    public init(
        query: String, systemPrompt: String?, styleReminder: String? = nil, maxTokens: Int = 512, history: ConversationHistory? = nil,
        enableThinking: Bool = false
    ) {
        self.query = query; self.systemPrompt = systemPrompt; self.styleReminder = styleReminder
        self.maxTokens = maxTokens; self.history = history; self.enableThinking = enableThinking
    }
}

public enum AnswerStage: String, Sendable, Equatable { case retrieving, thinking, generating }

/// The end of an answer: everything the chat stores and shows about it.
public struct AnswerResult: Sendable {
    /// The model's full text (thinking included, as the TS stores it).
    public var text: String
    public var sources: [Chunk]
    public var taskType: String
    public var retrieved: Bool
    public var retrievalMs: Double?
    public var tokensBefore: Int?
    public var tokensAfter: Int?
    /// "chat-template" or "plain".
    public var promptFormat: String
    public var metrics: GenerationMetrics?

    public init(
        text: String, sources: [Chunk], taskType: String, retrieved: Bool, retrievalMs: Double?, tokensBefore: Int?, tokensAfter: Int?,
        promptFormat: String, metrics: GenerationMetrics?
    ) {
        self.text = text; self.sources = sources; self.taskType = taskType; self.retrieved = retrieved; self.retrievalMs = retrievalMs
        self.tokensBefore = tokensBefore; self.tokensAfter = tokensAfter; self.promptFormat = promptFormat; self.metrics = metrics
    }
}

public enum AnswerEvent: Sendable {
    case stage(AnswerStage)
    /// The passages the model will read, numbered [1]..[n] in this order, with what compression saved.
    case sources(chunks: [Chunk], retrievalMs: Double, tokensBefore: Int, tokensAfter: Int)
    case piece(String)
    case done(AnswerResult)
}

/// The default answer path, the one the app runs when neither Deep Research nor adaptive routing is on (the eval's
/// fixed-model plan in src/routing/executor.ts): classify; retrieve and keep the answering sentences unless the task needs no
/// documents; then generate with the model's own chat template (a hand-built prompt with stop words only for a model without
/// one). Same prompts as the TS (golden tests).
public final class AnswerPipeline: Sendable {
    /// Passages retrieved per answer (src/rag/pure.ts ANSWER_CONTEXT_CHUNKS).
    public static let answerContextChunks = RagPure.answerContextChunks
    /// Turn ends for the hand-built prompt only (src/inference/LlamaEngine.ts DEFAULT_STOP_SEQUENCES).
    public static let defaultStopSequences = AnswerStopSequences.plain

    private let session: any TextModelSession
    private let retrieve: @Sendable (String, Int) async throws -> [Chunk]
    private let classify: @Sendable (String) -> String
    private let retrievalIrrelevant: @Sendable (String) -> Bool
    private let clock: @Sendable () -> Double

    /// - retrieve: `Retriever.retrieve(query, topK:)` on the phone.
    /// - classify: classifyTask's name for a query ("lookup", "greeting", …); retrievalIrrelevant: isRetrievalIrrelevant for a task type name.
    public init(
        session: any TextModelSession,
        retrieve: @escaping @Sendable (String, Int) async throws -> [Chunk],
        classify: @escaping @Sendable (String) -> String,
        retrievalIrrelevant: @escaping @Sendable (String) -> Bool,
        clock: @escaping @Sendable () -> Double = monotonicMillis
    ) {
        self.session = session; self.retrieve = retrieve; self.classify = classify
        self.retrievalIrrelevant = retrievalIrrelevant; self.clock = clock
    }

    /// The pipeline with BoarRouting's classifier and a `Retriever`.
    public convenience init(session: any TextModelSession, retriever: Retriever, clock: @escaping @Sendable () -> Double = monotonicMillis) {
        self.init(
            session: session, retrieve: { q, k in try await retriever.retrieve(q, topK: k) },
            classify: { Classify.classifyTask($0).value }, retrievalIrrelevant: { name in TaskType(rawValue: name).map(Classify.isRetrievalIrrelevant) ?? false },
            clock: clock
        )
    }

    /// Stops the generation in flight: the stream still delivers `.done` with what was written. Dropping or cancelling the
    /// consumer's task stops it too.
    public func cancel() { session.cancel() }

    /// Streams stage changes, the sources, the text pieces and the final result. Failures (retrieval, the model) are thrown from the stream.
    public func answer(_ req: AnswerRequest) -> AsyncThrowingStream<AnswerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(req) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ req: AnswerRequest, emit: @Sendable (AnswerEvent) -> Void) async throws {
        let task = classify(req.query)
        var sources: [Chunk] = []
        var retrievalMs: Double?
        var before: Int?
        var after: Int?
        let retrieved = !retrievalIrrelevant(task)
        if retrieved {
            emit(.stage(.retrieving))
            let t0 = clock()
            // A follow-up ("What did he publish?") is searched with the previous question (FollowUp).
            let found = try await FollowUp.search(req.query, history: req.history, textOf: { (c: Chunk) in "\(c.title) \(c.body)" }) {
                try await retrieve($0, Self.answerContextChunks)
            }
            // Only the sentences that answer: a shorter prompt brings the first word sooner.
            let c = Compress.forAnswer(found.searchedFor, found.chunks, taskType: task)
            let ms = clock() - t0
            retrievalMs = ms
            sources = c.chunks
            before = c.tokensBefore
            after = c.tokensAfter
            emit(.sources(chunks: sources, retrievalMs: ms, tokensBefore: c.tokensBefore, tokensAfter: c.tokensAfter))
        }
        emit(.stage(.thinking))
        let useTemplate = session.capabilities.hasChatTemplate
        let input: GenerationRequest.Input
        if useTemplate {
            let messages = RagPure.assembleChatMessages(req.query, sources, systemPrompt: req.systemPrompt, history: req.history, styleReminder: req.styleReminder)
                .map { ChatMessage(role: $0.role, content: $0.content) }
            input = .messages(messages)
        } else {
            input = .prompt(RagPure.assemblePrompt(req.query, sources, systemPrompt: req.systemPrompt, history: req.history, styleReminder: req.styleReminder))
        }
        // llama.rn left enable_thinking at the template's default (on); here it's the user's tweak, off by default,
        // so a thinking model doesn't spend the answer's token cap reasoning.
        let request = GenerationRequest(
            input: input, sampling: Sampling(nPredict: req.maxTokens, temperature: 0.7, stops: useTemplate ? [] : AnswerStopSequences.plain),
            enableThinking: req.enableThinking
        )
        var text = ""
        var metrics: GenerationMetrics?
        var first = true
        for try await event in session.generate(request) {
            switch event {
            case .piece(let p):
                if first { first = false; emit(.stage(.generating)) }
                text += p
                emit(.piece(p))
            case .done(let m):
                metrics = m
            }
        }
        emit(.done(AnswerResult(
            text: text, sources: sources, taskType: task, retrieved: retrieved, retrievalMs: retrievalMs, tokensBefore: before,
            tokensAfter: after, promptFormat: useTemplate ? "chat-template" : "plain", metrics: metrics
        )))
    }
}
