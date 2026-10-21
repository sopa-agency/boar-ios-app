import BoarCore
import Foundation
import os

/// A language model served by llama-server on another computer in the network, behind the same seam as the on-device
/// model. Generations are serialized (one at a time, as on the phone); `cancel()` stops the request in flight and the
/// stream still ends with `.done` (stopReason "cancelled"), keeping what was written.
public final class RemoteSession: TextModelSession, @unchecked Sendable {
    public let server: RemoteServer
    public let info: ModelInfo
    public let capabilities: ModelCapabilities

    private let session: URLSession
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let gate = Gate()
    private static let log = BoarLog.logger("remote")

    private struct State {
        var running: Task<Void, Never>?
        var cancelled = false
        var closed = false
    }

    /// Checks the server first (`probe`), so a session only exists when there is a model to talk to.
    public static func connect(_ server: RemoteServer, session: URLSession = .shared) async throws -> RemoteSession {
        let status = try await server.probe(session: session)
        return RemoteSession(server: server, status: status, session: session)
    }

    public init(server: RemoteServer, status: RemoteServerStatus, session: URLSession = .shared) {
        self.server = server
        self.session = session
        info = ModelInfo(name: status.modelName, backend: "llama-server")
        capabilities = ModelCapabilities(hasChatTemplate: true, acceptsRawPrompt: true, supportsThinking: true,
                                         supportsPrewarm: false, contextTokens: status.contextTokens)
    }

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.gate.enter()
                defer { Task { await self.gate.leave() } }
                await self.run(request, continuation)
            }
            state.withLock { $0.running = task; $0.cancelled = false }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func cancel() {
        state.withLock { s in
            s.cancelled = true
            s.running?.cancel()
        }
    }

    public func close() async {
        let running = state.withLock { s -> Task<Void, Never>? in
            s.closed = true
            s.cancelled = true
            s.running?.cancel()
            return s.running
        }
        await running?.value
    }

    private func run(_ request: GenerationRequest, _ out: AsyncThrowingStream<GenerationEvent, Error>.Continuation) async {
        if state.withLock({ $0.closed }) { return out.finish(throwing: ModelSeamError.notLoaded) }
        let start = ContinuousClock.now
        var firstPiece: ContinuousClock.Instant?
        var generated = 0
        var finish = ""
        var timings: RemoteStream.Timings?
        let (path, json) = RemoteStream.body(for: request)
        do {
            let body = try JSONSerialization.data(withJSONObject: json)
            let (bytes, response) = try await session.bytes(for: server.request(path, body: body))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                var text = ""
                for try await line in bytes.lines { text += line; if text.count > 300 { break } }
                throw RemoteServerError.httpStatus(code, text)
            }
            for try await line in bytes.lines {
                guard let chunk = RemoteStream.parse(line: line) else { continue }
                if !chunk.text.isEmpty {
                    if firstPiece == nil { firstPiece = .now }
                    generated += 1
                    out.yield(.piece(chunk.text))
                }
                if let reason = chunk.finishReason { finish = reason }
                if let t = chunk.timings { timings = t }
            }
        } catch {
            let cancelled = state.withLock { $0.cancelled } || Task.isCancelled || (error as? URLError)?.code == .cancelled
            if !cancelled {
                Self.log.error("remote generation failed: \(String(describing: error), privacy: .public)")
                let message = (error as? RemoteServerError)?.description ?? (error as? URLError).map { RemoteServerError.unreachable($0.localizedDescription).description } ?? String(describing: error)
                return out.finish(throwing: ModelSeamError.generationFailed(message))
            }
            finish = "cancelled"
        }
        if state.withLock({ $0.cancelled }), finish.isEmpty { finish = "cancelled" }
        out.yield(.done(Self.metrics(start: start, firstPiece: firstPiece, pieces: generated, finish: finish, timings: timings)))
        out.finish()
    }

    static func metrics(start: ContinuousClock.Instant, firstPiece: ContinuousClock.Instant?, pieces: Int, finish: String,
                        timings: RemoteStream.Timings?) -> GenerationMetrics {
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        let total = ms(start.duration(to: .now))
        let ttft = firstPiece.map { ms(start.duration(to: $0)) } ?? -1
        let stop = switch finish {
        case "length": "length"
        case "cancelled": "cancelled"
        case "": ""
        default: "stop"
        }
        return GenerationMetrics(
            promptTokens: timings?.promptTokens ?? 0, promptTokensDecoded: timings?.promptTokens ?? 0,
            generatedTokens: timings?.predictedTokens ?? pieces, ttftMs: ttft,
            prefillMs: timings?.promptMs ?? 0, decodeMs: timings?.predictedMs ?? max(0, total - max(ttft, 0)),
            prefillTokPerSec: timings?.promptPerSecond ?? 0, decodeTokPerSec: timings?.predictedPerSecond ?? 0,
            totalMs: total, stopReason: stop)
    }
}

/// One generation at a time, in arrival order.
private actor Gate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}
