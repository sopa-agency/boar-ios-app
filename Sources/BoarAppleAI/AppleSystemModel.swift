import BoarCore
import Foundation
import FoundationModels
import os

/// Apple's on-device language model (Foundation Models, iOS 26+) behind the BOAR model seam.
///
/// - Input: `.messages` only (`acceptsRawPrompt == false`). The first system message is the session instructions, earlier turns
///   are replayed as a transcript, the last user message is the prompt (`ApplePromptPlan`). Each `generate` opens a fresh
///   `LanguageModelSession`, so the pipeline's message list is the only state (same as llama.cpp).
/// - Sampling: temperature, nucleus threshold, seed and `nPredict` map to `GenerationOptions` (`AppleOptionsPlan`);
///   topK / minP / repeatPenalty / thinking are ignored. `Sampling.stops` are enforced with `StopSequenceFilter`.
/// - Failures are thrown as `ModelSeamError`; `AppleAIFailure.of(error)` tells a guardrail violation or refusal apart.
/// - Calls are serialized; `cancel()` ends the running generation with `.done(stopReason: "cancelled")`.
@available(iOS 26.0, macOS 26.0, *)
public final class AppleSystemModel: TextModelSession, @unchecked Sendable {
    public static let backend = "apple-foundation-models"
    public static let displayName = "Apple on-device model"

    public let model: SystemLanguageModel
    private let tools: [any Tool]
    private let name: String
    private let log = BoarLog.logger("AppleAI")

    private struct State {
        var closed = false
        var nextID = 0
        var activeID: Int?
        var cancelRequested = false
        var handles: [Int: Task<Void, Never>] = [:]
        var prewarmed: (key: String, session: LanguageModelSession)?
    }
    private let lock = NSLock()
    private var state = State()
    private let gate = AsyncGate()

    /// `tools` are handed to every session (the iOS 27 document helper passes the Spotlight and OCR tools).
    public init(model: SystemLanguageModel = .default, tools: [any Tool] = [], name: String = AppleSystemModel.displayName) {
        self.model = model; self.tools = tools; self.name = name
    }

    /// Whether the model can run right now.
    public var availability: AppleModelAvailability { AppleModelAvailability(model.availability) }

    /// The context window in tokens (`SystemLanguageModel.contextSize`; 4096 before iOS 26.4, back-deployed).
    public var contextSize: Int { model.contextSize }

    public var info: ModelInfo {
        ModelInfo(name: name, backend: Self.backend, architecture: "apple-foundation", trainingContextTokens: contextSize)
    }

    public var capabilities: ModelCapabilities {
        ModelCapabilities(hasChatTemplate: true, acceptsRawPrompt: false, supportsThinking: false, supportsPrewarm: true, contextTokens: contextSize)
    }

    // MARK: Generation

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: GenerationEvent.self, throwing: Error.self)
        let id = lock.withLock { () -> Int in state.nextID += 1; return state.nextID }
        let task = Task { [self] in
            await gate.acquire()
            await run(id: id, request: request, continuation: continuation)
            lock.withLock {
                state.handles[id] = nil
                if state.activeID == id { state.activeID = nil }
            }
            await gate.release()
        }
        lock.withLock { state.handles[id] = task }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func cancel() {
        let handle: Task<Void, Never>? = lock.withLock {
            guard let id = state.activeID else { return nil }
            state.cancelRequested = true
            return state.handles[id]
        }
        handle?.cancel()
    }

    public func prewarm(_ input: GenerationRequest.Input, enableThinking: Bool) async {
        guard case .messages(let messages) = input, model.isAvailable else { return }
        let plan = (try? ApplePromptPlan.make(messages)) ?? ApplePromptPlan(
            instructions: messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n").nilIfEmpty,
            history: [], prompt: "")
        let session = LanguageModelSession(model: model, tools: tools, transcript: transcript(for: plan))
        session.prewarm(promptPrefix: plan.prompt.isEmpty ? nil : Prompt(plan.prompt))
        lock.withLock { state.prewarmed = (plan.prefixKey, session) }
    }

    public func close() async {
        lock.withLock { state.closed = true; state.prewarmed = nil }
        cancel()
        await gate.acquire()
        await gate.release()
    }

    private var isCancelRequested: Bool { lock.withLock { state.cancelRequested } }

    private func run(id: Int, request: GenerationRequest, continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation) async {
        let closed = lock.withLock { () -> Bool in
            state.activeID = id
            state.cancelRequested = false  // a cancel() before this generation started is lost (seam contract)
            return state.closed
        }
        if closed { continuation.finish(throwing: ModelSeamError.notLoaded); return }
        if Task.isCancelled { continuation.finish(); return }

        let plan: ApplePromptPlan
        do { plan = try ApplePromptPlan.make(request.input) } catch {
            continuation.finish(throwing: error); return
        }
        let availability = self.availability
        guard availability.isAvailable else {
            continuation.finish(throwing: AppleAIFailure.unavailable.seamError(availability.code)); return
        }
        let optionsPlan = AppleOptionsPlan.make(request.sampling)
        let session = takePrewarmed(plan.prefixKey) ?? LanguageModelSession(model: model, tools: tools, transcript: transcript(for: plan))
        let clock = ContinuousClock()
        let start = clock.now

        if request.sampling.nPredict <= 0 {
            // Prefill only (the seam's prewarm): read the prompt into the model's cache, generate nothing.
            session.prewarm(promptPrefix: Prompt(plan.prompt))
            continuation.yield(.done(GenerationMetrics(totalMs: start.duration(to: clock.now).ms, stopReason: "length")))
            continuation.finish()
            return
        }

        var filter = StopSequenceFilter(stops: request.sampling.stops)
        var differ = SnapshotDiffer()
        var emitted = ""
        var ttftMs: Double = -1
        var firstPieceAt: ContinuousClock.Instant?
        var usage = UsageCounts()
        var cancelled = false

        do {
            let stream = session.streamResponse(to: plan.prompt, options: optionsPlan.generationOptions)
            for try await snapshot in stream {
                if #available(iOS 27, macOS 27, visionOS 27, *) { usage = UsageCounts(snapshot.usage) }
                if isCancelRequested { cancelled = true; break }
                let out = filter.push(differ.delta(snapshot.content))
                if !out.isEmpty {
                    if firstPieceAt == nil { firstPieceAt = clock.now; ttftMs = start.duration(to: firstPieceAt!).ms }
                    emitted += out
                    continuation.yield(.piece(out))
                }
                if filter.hitStop { break }
            }
        } catch {
            if isCancelRequested { cancelled = true }
            else if Task.isCancelled || error is CancellationError { continuation.finish(); return }  // consumer went away
            else {
                let mapped = AppleAIErrorMapping.map(error)
                log.error("generation failed: \(mapped.description, privacy: .public)")
                continuation.finish(throwing: mapped); return
            }
        }
        if !cancelled, isCancelRequested { cancelled = true }
        if !cancelled, Task.isCancelled { continuation.finish(); return }  // consumer dropped the stream

        let tail = filter.finish()
        if !tail.isEmpty {
            if firstPieceAt == nil { firstPieceAt = clock.now; ttftMs = start.duration(to: firstPieceAt!).ms }
            emitted += tail
            continuation.yield(.piece(tail))
        }
        if usage.generated == 0 { usage = await fallbackCounts(plan: plan, text: emitted) }
        let end = clock.now
        let totalMs = start.duration(to: end).ms
        let prefillMs = ttftMs >= 0 ? ttftMs : totalMs
        let decodeMs = firstPieceAt.map { $0.duration(to: end).ms } ?? 0
        let metrics = GenerationMetrics(
            promptTokens: usage.prompt,
            promptTokensDecoded: max(0, usage.prompt - usage.cached),
            generatedTokens: usage.generated,
            ttftMs: ttftMs,
            prefillMs: prefillMs,
            decodeMs: decodeMs,
            prefillTokPerSec: prefillMs > 0 && usage.prompt > 0 ? Double(usage.prompt) / (prefillMs / 1000) : 0,
            decodeTokPerSec: decodeMs > 0 && usage.generated > 1 ? Double(usage.generated - 1) / (decodeMs / 1000) : 0,
            totalMs: totalMs,
            stopReason: AppleStopReason.derive(
                hitStop: filter.hitStop, cancelled: cancelled, generatedTokens: usage.generated,
                maximumResponseTokens: optionsPlan.maximumResponseTokens))
        continuation.yield(.done(metrics))
        continuation.finish()
    }

    private func takePrewarmed(_ key: String) -> LanguageModelSession? {
        lock.withLock {
            guard let p = state.prewarmed, p.key == key else { return nil }
            state.prewarmed = nil
            return p.session
        }
    }

    /// Token counts before iOS 27 (no `usage`): `SystemLanguageModel.tokenCount(for:)` on iOS 26.4+, else unknown (0).
    private func fallbackCounts(plan: ApplePromptPlan, text: String) async -> UsageCounts {
        guard #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) else { return UsageCounts() }
        let generated = text.isEmpty ? 0 : ((try? await model.tokenCount(for: text)) ?? 0)
        var entries = Array(transcript(for: plan))
        entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: plan.prompt))])))
        let prompt = (try? await model.tokenCount(for: entries)) ?? 0
        return UsageCounts(prompt: prompt, cached: 0, generated: generated)
    }

    // MARK: Transcript

    /// Instructions (+ tool definitions) and the replayed history, without the final prompt.
    func transcript(for plan: ApplePromptPlan) -> Transcript {
        var entries: [Transcript.Entry] = []
        let toolDefinitions = tools.map { Transcript.ToolDefinition(tool: $0) }
        if plan.instructions != nil || !toolDefinitions.isEmpty {
            let segments: [Transcript.Segment] = plan.instructions.map { [.text(Transcript.TextSegment(content: $0))] } ?? []
            entries.append(.instructions(Transcript.Instructions(segments: segments, toolDefinitions: toolDefinitions)))
        }
        for turn in plan.history {
            switch turn {
            case .user(let s):
                entries.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: s))])))
            case .assistant(let s):
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: s))])))
            }
        }
        return Transcript(entries: entries)
    }
}

// MARK: - Helpers

@available(iOS 26.0, macOS 26.0, *)
extension AppleOptionsPlan {
    /// The Foundation Models options for this plan.
    public var generationOptions: GenerationOptions {
        let mode: GenerationOptions.SamplingMode? = switch sampling {
        case .systemDefault: nil
        case .greedy: .greedy
        case .nucleus(let threshold, let seed): .random(probabilityThreshold: threshold, seed: seed)
        }
        return GenerationOptions(samplingMode: mode, temperature: temperature, maximumResponseTokens: maximumResponseTokens)
    }
}

struct UsageCounts: Equatable {
    var prompt = 0
    var cached = 0
    var generated = 0

    init(prompt: Int = 0, cached: Int = 0, generated: Int = 0) {
        self.prompt = prompt; self.cached = cached; self.generated = generated
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    init(_ usage: LanguageModelSession.Usage) {
        self.init(prompt: usage.input.totalTokenCount, cached: usage.input.cachedTokenCount, generated: usage.output.totalTokenCount)
    }
}

/// FIFO async mutex: one generation at a time per session.
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

extension Duration {
    var ms: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
