import Foundation

// MARK: - Helpers every consumer and implementation shares

/// The text and measurements of one finished generation.
public struct GenerationOutput: Sendable, Equatable {
    public var text: String
    public var metrics: GenerationMetrics?
    /// The time limit stopped it; `text` is what was written until then.
    public var timedOut: Bool
    public init(text: String, metrics: GenerationMetrics?, timedOut: Bool) {
        self.text = text; self.metrics = metrics; self.timedOut = timedOut
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

extension TextModelSession {
    /// Runs one generation to the end: collects the pieces (also handing each to `onPiece`), and on `timeout` calls `cancel()`
    /// and keeps what was written (the Kotlin `SessionEngine`). Rethrows the stream's failure.
    public func generateText(
        _ request: GenerationRequest, timeout: Duration? = nil, onPiece: (@Sendable (String) -> Void)? = nil
    ) async throws -> GenerationOutput {
        let flag = TimeoutFlag()
        let timer: Task<Void, Never>? = timeout.map { limit in
            Task { [self] in
                try? await Task.sleep(for: limit)
                if !Task.isCancelled { flag.set(); cancel() }
            }
        }
        defer { timer?.cancel() }
        var text = ""
        var metrics: GenerationMetrics?
        for try await event in generate(request) {
            switch event {
            case .piece(let p): text += p; onPiece?(p)
            case .done(let m): metrics = m
            }
        }
        return GenerationOutput(text: text, metrics: metrics, timedOut: flag.isSet)
    }

    /// Milliseconds overload (`EngineTweaks.stageTimeoutMs`); nil = no limit.
    public func generateText(
        _ request: GenerationRequest, timeoutMs: Int64?, onPiece: (@Sendable (String) -> Void)? = nil
    ) async throws -> GenerationOutput {
        try await generateText(request, timeout: timeoutMs.map { .milliseconds($0) }, onPiece: onPiece)
    }
}

/// Wraps a session and reports every finished generation's metrics (Kotlin `LlamaSession.onGenerated`: the model host watches for
/// decode stalls with repacked weights). Everything else passes through.
public final class MetricsObservingSession: TextModelSession {
    private let base: any TextModelSession
    private let observer: @Sendable (GenerationMetrics) -> Void

    public init(_ base: any TextModelSession, onGenerated observer: @escaping @Sendable (GenerationMetrics) -> Void) {
        self.base = base; self.observer = observer
    }

    public var info: ModelInfo { base.info }
    public var capabilities: ModelCapabilities { base.capabilities }
    public func cancel() { base.cancel() }
    public func prewarm(_ input: GenerationRequest.Input, enableThinking: Bool) async { await base.prewarm(input, enableThinking: enableThinking) }
    public func close() async { await base.close() }

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        let inner = base.generate(request)
        let observer = observer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await e in inner {
                        if case .done(let m) = e { observer(m) }
                        continuation.yield(e)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Cuts a streamed text at the first stop string, holding back any tail that might still become one. For backends that can't
/// enforce stops natively (Foundation Models); llama.cpp stops inside the sampler loop.
public struct StopSequenceFilter: Sendable {
    public let stops: [String]
    private var pending = ""
    public private(set) var hitStop = false

    public init(stops: [String]) { self.stops = stops.filter { !$0.isEmpty } }

    /// Feeds a piece; returns the text that is safe to show now. After `hitStop` it returns "" for everything.
    public mutating func push(_ piece: String) -> String {
        if hitStop { return "" }
        pending += piece
        var cut: String.Index?
        for s in stops {
            if let r = pending.range(of: s), cut == nil || r.lowerBound < cut! { cut = r.lowerBound }
        }
        if let cut {
            let out = String(pending[..<cut])
            pending = ""
            hitStop = true
            return out
        }
        // Hold back the longest suffix that is a proper prefix of some stop.
        var keep = 0
        for s in stops {
            let maxLen = min(s.count - 1, pending.count)
            if maxLen < 1 { continue }
            for n in stride(from: maxLen, through: 1, by: -1) where pending.hasSuffix(String(s.prefix(n))) {
                keep = max(keep, n)
                break
            }
        }
        let emitCount = pending.count - keep
        let idx = pending.index(pending.startIndex, offsetBy: emitCount)
        let out = String(pending[..<idx])
        pending = String(pending[idx...])
        return out
    }

    /// The end of the stream: whatever was held back is not a stop and can be shown.
    public mutating func finish() -> String {
        defer { pending = "" }
        return hitStop ? "" : pending
    }
}
