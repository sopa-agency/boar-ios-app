import BoarCore
import BoarRAG
import BoarRouting
import Foundation

public struct PipelineInput: Sendable {
    public var query: String
    public var systemPrompt: String?
    public var styleReminder: String?
    public var history: ConversationHistory?
    public init(query: String, systemPrompt: String? = nil, styleReminder: String? = nil, history: ConversationHistory? = nil) {
        self.query = query; self.systemPrompt = systemPrompt; self.styleReminder = styleReminder; self.history = history
    }
}

public struct Verification: Sendable, Equatable {
    public var status: String
    public var note: String?
    public init(status: String, note: String? = nil) { self.status = status; self.note = note }
}

public struct PipelineResult: Sendable {
    public var answer: String
    public var plan: Router.RoutingPlan
    public var citations: [Chunk]
    public var verification: Verification
    public var warnings: [String]
    public var stepsExecuted: Int
    public var modelSwitches: Int
    public var timedOut: Bool
    public var crossMessageModelSwitch: Bool
    public var modelResidency: String?
    public var modelLoadMs: Double?
    public var ttftMs: Double?
    public var retrievalMs: Double?
    public var contextTokensBefore: Int?
    public var contextTokensAfter: Int?
    public var generationLatencyMs: Double?
    public var promptFormat: String?
    public var metrics: GenerationMetrics?
    public var stopped: Bool
}

/// Runs a routing plan step by step (port of src/routing/executor.ts executeRoutingPlan): retrieve and compress, generate
/// with the plan's model (loading it if another is resident), verify the answer against its sources. Timing and residency
/// are measured around the generate step only. Each generation has the user's time limit (Auto grows with its token cap).
public struct PlanExecutor: Sendable {
    private let host: any ModelHost
    private let retrieve: @Sendable (String, Int) async throws -> [Chunk]
    /// classifyTask's name for the query (the compression budget depends on it).
    private let classify: @Sendable (String) -> String
    private let clock: @Sendable () -> Double
    /// Time limit for a generation of n tokens (`EngineTweaks.stageTimeoutMs`, the user's setting); nil = none.
    private let timeoutFor: @Sendable (Int) -> Int64?

    public init(
        host: any ModelHost,
        retrieve: @escaping @Sendable (String, Int) async throws -> [Chunk],
        classify: @escaping @Sendable (String) -> String,
        clock: @escaping @Sendable () -> Double = monotonicMillis,
        timeoutFor: @escaping @Sendable (Int) -> Int64? = { EngineTweaks().stageTimeoutMs(nPredict: $0) }
    ) {
        self.host = host; self.retrieve = retrieve; self.classify = classify; self.clock = clock; self.timeoutFor = timeoutFor
    }

    /// The executor with BoarRouting's classifier and a `Retriever`.
    public init(
        host: any ModelHost, retriever: Retriever, clock: @escaping @Sendable () -> Double = monotonicMillis,
        timeoutFor: @escaping @Sendable (Int) -> Int64? = { EngineTweaks().stageTimeoutMs(nPredict: $0) }
    ) {
        self.init(
            host: host, retrieve: { q, k in try await retriever.retrieve(q, topK: k) }, classify: { Classify.classifyTask($0).value },
            clock: clock, timeoutFor: timeoutFor
        )
    }

    public func execute(
        plan: Router.RoutingPlan,
        input: PipelineInput,
        onToken: (@Sendable (String) -> Void)? = nil,
        onStepStart: ((Router.RoutingStep) -> Void)? = nil,
        shouldStop: @Sendable () -> Bool = { false }
    ) async throws -> PipelineResult {
        var warnings: [String] = []
        var answer = ""
        var citations: [Chunk] = []
        var verification = Verification(status: "not_applicable")
        var steps = 0
        var loadedModelId: String?
        var engine: (any StepEngine)?
        var switches = 0
        let residentBefore = await host.residentFilename()
        var residency: String?
        var loadMs: Double?
        var ttft: Double?
        var retrievalMs: Double?
        var before: Int?
        var after: Int?
        var genLatency: Double?
        var format: String?
        var metrics: GenerationMetrics?
        var captured = false
        var timedOut = false

        func result(stopped: Bool) async -> PipelineResult {
            let cross: Bool
            if let residentBefore { cross = await host.residentFilename() != residentBefore } else { cross = false }
            return PipelineResult(
                answer: answer, plan: plan, citations: citations, verification: verification, warnings: warnings, stepsExecuted: steps,
                modelSwitches: switches, timedOut: timedOut, crossMessageModelSwitch: cross, modelResidency: residency, modelLoadMs: loadMs,
                ttftMs: ttft, retrievalMs: retrievalMs, contextTokensBefore: before, contextTokensAfter: after,
                generationLatencyMs: genLatency, promptFormat: format, metrics: metrics, stopped: stopped
            )
        }

        func ensure(_ modelId: String?) async throws -> Bool {
            guard let modelId, !modelId.isEmpty else { return false }
            guard let filename = await host.filenameOf(modelId) else { warnings.append("model-unavailable:\(modelId)"); return false }
            let alreadyResident = loadedModelId == modelId || (loadedModelId == nil && residentBefore == filename)
            if !alreadyResident || engine == nil {
                let t0 = clock()
                guard let loaded = try await host.load(modelId) else { warnings.append("model-unavailable:\(modelId)"); return false }
                engine = loaded
                let ms = clock() - t0
                if !alreadyResident {
                    if loadedModelId != nil { switches += 1 }
                    if !captured { residency = residentBefore == nil ? "cold" : "switched"; loadMs = ms; captured = true }
                }
            }
            if alreadyResident && !captured { residency = "resident"; loadMs = 0.0; captured = true }
            loadedModelId = modelId
            return true
        }

        for step in plan.steps {
            if shouldStop() { return await result(stopped: true) }
            onStepStart?(step)
            switch step.type {
            case .retrieve:
                let t0 = clock()
                // A follow-up ("What did he publish?") is searched with the previous question (FollowUp).
                let found = try await FollowUp.search(input.query, history: input.history, textOf: { (c: Chunk) in "\(c.title) \(c.body)" }) {
                    try await retrieve($0, AnswerPipeline.answerContextChunks)
                }
                let c = Compress.forAnswer(found.searchedFor, found.chunks, taskType: classify(input.query))
                retrievalMs = clock() - t0
                citations = c.chunks
                before = c.tokensBefore
                after = c.tokensAfter
                steps += 1
            case .generate:
                if try await !ensure(step.modelId) {
                    if step.required { warnings.append("generate-step-failed-no-model"); return await result(stopped: false) }
                    continue
                }
                let e = engine!
                // Every model uses its own chat template when its GGUF ships one ("if-embedded").
                format = e.hasChatTemplate ? "chat-template" : "plain"
                let n = step.maxTokens ?? 512
                let limit = step.timeoutMs ?? timeoutFor(n)
                let req: GenRequest
                if e.hasChatTemplate {
                    req = GenRequest(
                        messages: RagPure.assembleChatMessages(input.query, citations, systemPrompt: input.systemPrompt, history: input.history, styleReminder: input.styleReminder),
                        prompt: nil, nPredict: n, temperature: 0.7, stops: [], timeoutMs: limit
                    )
                } else {
                    req = GenRequest(
                        messages: nil,
                        prompt: RagPure.assemblePrompt(input.query, citations, systemPrompt: input.systemPrompt, history: input.history, styleReminder: input.styleReminder),
                        nPredict: n, temperature: 0.7, stops: AnswerPipeline.defaultStopSequences, timeoutMs: limit
                    )
                }
                let first = LockedBox<Double?>(nil)
                let now = self.clock
                let start = now()
                let g = try await e.generate(req) { piece in
                    first.withValue { if $0 == nil { $0 = now() } }
                    onToken?(piece)
                }
                let end = now()
                answer = g.text
                metrics = g.metrics
                if g.timedOut { timedOut = true }
                let firstToken = (first.value ?? end) - start
                ttft = firstToken
                genLatency = end - start - firstToken
                steps += 1
            case .verify:
                if citations.isEmpty || answer.isEmpty { verification = Verification(status: "not_applicable"); continue }
                if try await !ensure(step.modelId) { verification = Verification(status: "not_applicable"); continue }
                let e = engine!
                let verifyInput = Verify.buildInput(input.query, answer, citations)
                let n = step.maxTokens ?? 200
                let limit = step.timeoutMs ?? timeoutFor(n)
                let req: GenRequest
                if e.hasChatTemplate {
                    req = GenRequest(
                        messages: [PromptMessage(role: "system", content: Verify.instruction), PromptMessage(role: "user", content: verifyInput)],
                        prompt: nil, nPredict: n, temperature: 0.2, stops: [], timeoutMs: limit
                    )
                } else {
                    req = GenRequest(
                        messages: nil, prompt: "\(Verify.instruction)\n\n\(verifyInput)\n\nVerdict:", nPredict: n, temperature: 0.2,
                        stops: AnswerPipeline.defaultStopSequences, timeoutMs: limit
                    )
                }
                let g = try await e.generate(req, onToken: nil)
                if g.timedOut { timedOut = true }
                verification = Verify.parse(g.text)
                steps += 1
            default:
                warnings.append("unhandled-step-type:\(step.type.value)")
            }
        }
        return await result(stopped: false)
    }
}

/// Evidence-grounded verification (port of src/routing/verify.ts).
public enum Verify {
    public static let instruction = "You are checking whether an answer is actually supported by the evidence below — "
        + "not whether it's well-written, not whether you personally agree with it. "
        + "Respond with exactly one word first: SUPPORTED, PARTIAL, or UNSUPPORTED, then a "
        + "single sentence explaining why."

    public static func buildInput(_ query: String, _ answer: String, _ citations: [Chunk]) -> String {
        let evidence = citations.enumerated().map { "[\($0.offset + 1)] \($0.element.title)\n\($0.element.body)" }.joined(separator: "\n\n")
        return "Question: \(query)\n\nEvidence:\n\(evidence)\n\nAnswer to check:\n\(answer)"
    }

    public static func parse(_ text: String) -> Verification {
        let trimmed = JsString.trim(text)
        let upper = trimmed.uppercased()
        // JavaScript slices UTF-16 units, as take() does.
        let cut = trimmed.u16Take(200)
        let note: String? = cut.isEmpty ? nil : cut
        if upper.hasPrefix("SUPPORTED") { return Verification(status: "passed", note: note) }
        if upper.hasPrefix("UNSUPPORTED") { return Verification(status: "failed", note: note) }
        if upper.hasPrefix("PARTIAL") { return Verification(status: "uncertain", note: note) }
        return Verification(status: "uncertain", note: note)
    }
}
