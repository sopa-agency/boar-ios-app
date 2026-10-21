import Foundation
import Testing
@testable import BoarCore

/// A scripted session that exercises the contract every real backend must meet.
final class FakeSession: TextModelSession, @unchecked Sendable {
    let info = ModelInfo(name: "fake", backend: "test")
    let capabilities: ModelCapabilities
    private let lock = NSLock()
    private var cancelled = false
    private var _requests: [GenerationRequest] = []
    private let pieces: [String]
    private let pieceDelay: Duration

    init(pieces: [String], pieceDelay: Duration = .zero, hasChatTemplate: Bool = true) {
        self.pieces = pieces; self.pieceDelay = pieceDelay
        capabilities = ModelCapabilities(hasChatTemplate: hasChatTemplate, acceptsRawPrompt: !hasChatTemplate)
    }

    var requests: [GenerationRequest] { lock.withLock { _requests } }
    func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }
    func close() async {}

    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        lock.withLock { _requests.append(request); cancelled = false }
        return AsyncThrowingStream { c in
            let task = Task {
                var n = 0
                var reason = "eos"
                for p in pieces {
                    if isCancelled { reason = "cancelled"; break }
                    if pieceDelay != .zero { try? await Task.sleep(for: pieceDelay) }
                    if isCancelled { reason = "cancelled"; break }
                    c.yield(.piece(p)); n += 1
                }
                c.yield(.done(GenerationMetrics(generatedTokens: n, stopReason: reason)))
                c.finish()
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite struct ModelSeamTests {
    @Test func generateTextCollectsPiecesAndMetrics() async throws {
        let s = FakeSession(pieces: ["Hel", "lo"])
        let seen = PieceLog()
        let out = try await s.generateText(GenerationRequest(messages: [ChatMessage(role: .user, content: "hi")]), onPiece: { seen.add($0) })
        #expect(out.text == "Hello" && !out.timedOut)
        #expect(out.metrics?.generatedTokens == 2 && out.metrics?.stopReason == "eos")
        #expect(seen.all == ["Hel", "lo"])
        #expect(s.requests.first?.input == .messages([ChatMessage(role: "user", content: "hi")]))
    }

    @Test func aTimeLimitCancelsAndKeepsWhatWasWritten() async throws {
        let s = FakeSession(pieces: Array(repeating: "x", count: 200), pieceDelay: .milliseconds(20))
        let out = try await s.generateText(GenerationRequest(prompt: "p"), timeoutMs: 150)
        #expect(out.timedOut)
        #expect(out.metrics?.stopReason == "cancelled")
        #expect(!out.text.isEmpty && out.text.count < 200)
    }

    @Test func noTimeLimitMeansNoTimer() async throws {
        let s = FakeSession(pieces: ["a"])
        let out = try await s.generateText(GenerationRequest(prompt: "p"), timeoutMs: nil)
        #expect(out.text == "a" && !out.timedOut)
    }

    @Test func theObservingSessionReportsMetricsAndPassesEverythingThrough() async throws {
        let base = FakeSession(pieces: ["a", "b", "c"])
        let log = MetricsLog()
        let s = MetricsObservingSession(base, onGenerated: { log.add($0) })
        let out = try await s.generateText(GenerationRequest(prompt: "p"))
        #expect(out.text == "abc")
        #expect(log.all.map(\.generatedTokens) == [3])
        #expect(s.info.name == "fake" && s.capabilities == base.capabilities)
    }

    @Test func nullEmbedderGivesTheEmptyVector() async throws {
        let e: any TextEmbedder = NullEmbedder()
        #expect(try await e.embed("anything").isEmpty)
    }

    @Test func requestsKeepTheirInputKind() {
        let m = GenerationRequest(messages: [ChatMessage(role: .system, content: "s")], sampling: Sampling(nPredict: 0), enableThinking: true)
        #expect(m.enableThinking && m.sampling.nPredict == 0)
        #expect(GenerationRequest(prompt: "x").input == .prompt("x"))
        #expect(AnswerStopSequences.plain.count == 4)
    }

    // MARK: StopSequenceFilter

    private func run(_ pieces: [String], stops: [String]) -> (text: String, hit: Bool) {
        var f = StopSequenceFilter(stops: stops)
        var out = ""
        for p in pieces { out += f.push(p) }
        out += f.finish()
        return (out, f.hitStop)
    }

    @Test func stopFilterPassesTextWithoutStops() {
        #expect(run(["Hello ", "world"], stops: ["\nUser:"]).text == "Hello world")
        #expect(run(["Hello ", "world"], stops: []).text == "Hello world")
    }

    @Test func stopFilterCutsAtTheStopAcrossPieces() {
        let r = run(["The answer.", "\nUs", "er: next"], stops: ["\nUser:", "\nQuestion:"])
        #expect(r.text == "The answer." && r.hit)
        #expect(run(["a\n\nUser: b"], stops: ["\nUser:", "\n\nUser:"]).text == "a")
    }

    @Test func stopFilterHoldsBackAPartialStopThenReleasesItAtTheEnd() {
        var f = StopSequenceFilter(stops: ["\nUser:"])
        #expect(f.push("done\nUs") == "done")
        #expect(f.finish() == "\nUs")
        let r = run(["x\n", "Us", "ing"], stops: ["\nUser:"])
        #expect(r.text == "x\nUsing" && !r.hit)
    }

    @Test func stopFilterEmitsNothingAfterTheStop() {
        var f = StopSequenceFilter(stops: ["END"])
        #expect(f.push("abEND") == "ab")
        #expect(f.push("more") == "")
        #expect(f.finish() == "")
    }
}

final class PieceLog: @unchecked Sendable {
    private let lock = NSLock(); private var items: [String] = []
    func add(_ s: String) { lock.withLock { items.append(s) } }
    var all: [String] { lock.withLock { items } }
}
final class MetricsLog: @unchecked Sendable {
    private let lock = NSLock(); private var items: [GenerationMetrics] = []
    func add(_ m: GenerationMetrics) { lock.withLock { items.append(m) } }
    var all: [GenerationMetrics] { lock.withLock { items } }
}
