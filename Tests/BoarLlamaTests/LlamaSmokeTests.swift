import BoarCore
import Foundation
import Testing

@testable import BoarLlama

// Model-backed tests. They run only when BOAR_TEST_GGUF (a chat model) / BOAR_TEST_EMBED_GGUF (an embedding model) point to files:
//   BOAR_TEST_GGUF=.../Qwen2.5-1.5B-Instruct-Q4_K_M.gguf BOAR_TEST_EMBED_GGUF=.../bge-small-en-v1.5-q8_0.gguf \
//     swift test --scratch-path .build/llama --filter BoarLlamaTests

private let chatModelPath = ProcessInfo.processInfo.environment["BOAR_TEST_GGUF"]
private let embedModelPath = ProcessInfo.processInfo.environment["BOAR_TEST_EMBED_GGUF"]

private func report(_ line: String) {
    FileHandle.standardError.write(Data("[BoarLlama] \(line)\n".utf8))
}

private struct Collected {
    var pieces: [String] = []
    var done: [GenerationMetrics] = []
    var text: String { pieces.joined() }
}

private func collect(_ stream: AsyncThrowingStream<GenerationEvent, Error>, onPiece: (() -> Void)? = nil) async throws -> Collected {
    var c = Collected()
    for try await e in stream {
        switch e {
        case .piece(let p): c.pieces.append(p); onPiece?()
        case .done(let m): c.done.append(m)
        }
    }
    return c
}

private let askQuestion = [
    ChatMessage(role: .system, content: "You are a concise assistant."),
    ChatMessage(role: .user, content: "Name three primary colours."),
]

/// One serialized parent so the chat and embedding suites never compete for the CPU (their numbers are timings).
@Suite("Llama smoke", .serialized)
struct LlamaSmokeTests {

@Suite("chat model", .enabled(if: chatModelPath != nil))
struct Chat {
    // BOAR_TEST_THREADS / BOAR_TEST_GPU_LAYERS vary the run for timing comparisons (defaults: 4 threads, Metal on a Mac or device).
    private var threads: Int { Int(ProcessInfo.processInfo.environment["BOAR_TEST_THREADS"] ?? "") ?? 4 }
    private var gpuLayers: Int? { Int(ProcessInfo.processInfo.environment["BOAR_TEST_GPU_LAYERS"] ?? "") }

    private func load(nCtx: Int = 2048) async throws -> LlamaSession {
        try await LlamaSession.load(path: try #require(chatModelPath), params: EngineParams(nCtx: nCtx, threads: threads), gpuLayers: gpuLayers)
    }

    @Test func loadsAndGenerates16Tokens() async throws {
        let t0 = Date()
        let s = try await load()
        let loadSeconds = Date().timeIntervalSince(t0)
        report("system: " + LlamaSession.systemInfo())
        #expect(s.info.backend == "llama.cpp")
        #expect(s.info.architecture != nil)
        #expect(s.capabilities.hasChatTemplate)
        #expect(s.capabilities.acceptsRawPrompt)
        #expect(s.capabilities.supportsPrewarm)
        #expect(s.capabilities.contextTokens == 2048)

        let formatted = try await s.formatChat(askQuestion, enableThinking: false)
        #expect(formatted.prompt.contains("Name three primary colours."))

        let long = [ChatMessage(role: .user, content: "Write a long, detailed essay about the history of the sea.")]
        let c = try await collect(s.generate(GenerationRequest(messages: long, sampling: Sampling(nPredict: 16, temperature: 0, seed: 1))))
        #expect(c.done.count == 1)
        #expect(!c.pieces.isEmpty)
        #expect(c.pieces.allSatisfy { !$0.isEmpty })
        let m = try #require(c.done.first)
        #expect(m.stopReason == "length")
        #expect(m.generatedTokens == 16)
        #expect(m.promptTokens > 0 && m.promptTokensDecoded == m.promptTokens)
        #expect(m.ttftMs > 0 && m.totalMs >= m.ttftMs)
        #expect(m.decodeTokPerSec > 0 && m.prefillTokPerSec > 0)
        #expect(m.error == nil)
        report(String(format: "%@ (gpuLayers %d, threads %d): load %.2f s, prefill %.1f tok/s (%d tok), decode %.1f tok/s, ttft %.0f ms, text: %@",
                      s.info.name, gpuLayers ?? LlamaSession.defaultGpuLayers, threads, loadSeconds, m.prefillTokPerSec, m.promptTokens, m.decodeTokPerSec, m.ttftMs, c.text.debugDescription))
        await s.close()
    }

    @Test func greedyIsDeterministicAndKeepsThePromptPrefix() async throws {
        let s = try await load()
        let req = GenerationRequest(messages: askQuestion, sampling: Sampling(nPredict: 12, temperature: 0))
        let a = try await collect(s.generate(req))
        let b = try await collect(s.generate(req))
        #expect(a.text == b.text)
        let mb = try #require(b.done.first)
        // the second run reuses the whole cached prompt but the last token
        #expect(mb.promptTokensDecoded == 1)
        await s.close()
    }

    @Test func prewarmReadsTheSystemHeadIntoTheCache() async throws {
        let s = try await load()
        await s.prewarm(.messages([askQuestion[0], ChatMessage(role: .user, content: "x")]), enableThinking: false)
        let c = try await collect(s.generate(GenerationRequest(messages: askQuestion, sampling: Sampling(nPredict: 4, temperature: 0))))
        let m = try #require(c.done.first)
        #expect(m.promptTokensDecoded < m.promptTokens)
        await s.close()
    }

    @Test func cancelEndsWithDoneNotAnError() async throws {
        let s = try await load()
        var seen = 0
        let c = try await collect(s.generate(GenerationRequest(messages: askQuestion, sampling: Sampling(nPredict: 400, temperature: 0.7)))) {
            seen += 1
            if seen == 3 { s.cancel() }
        }
        let m = try #require(c.done.first)
        #expect(c.done.count == 1)
        #expect(m.stopReason == "cancelled")
        #expect(m.generatedTokens < 400)
        #expect(!c.text.isEmpty)
        // the session keeps working afterwards
        let again = try await collect(s.generate(GenerationRequest(messages: askQuestion, sampling: Sampling(nPredict: 4, temperature: 0))))
        #expect(again.done.first?.stopReason == "length")
        await s.close()
    }

    @Test func generateTextTimeoutKeepsTheTextWritten() async throws {
        let s = try await load()
        let essay = [ChatMessage(role: .user, content: "Write a very long, detailed essay about the history of the sea.")]
        let out = try await s.generateText(
            GenerationRequest(messages: essay, sampling: Sampling(nPredict: 4000, temperature: 0.7)), timeout: .milliseconds(600)
        )
        #expect(out.timedOut)
        #expect(out.metrics?.stopReason == "cancelled")
        #expect((out.metrics?.generatedTokens ?? 0) == 0 || !out.text.isEmpty)  // a slow CPU run may be cut during prefill
        await s.close()
    }

    @Test func stopSequencesAreHonouredAndNotEmitted() async throws {
        let s = try await load()
        let msgs = [ChatMessage(role: .user, content: "Count from 1 to 20 separated by spaces. Output only the numbers.")]
        let c = try await collect(s.generate(GenerationRequest(messages: msgs, sampling: Sampling(nPredict: 80, temperature: 0, stops: ["8"]))))
        let m = try #require(c.done.first)
        #expect(m.stopReason == "stop")
        #expect(!c.text.contains("8"))
        #expect(c.text.contains("7"))
        await s.close()
    }

    @Test func rawPromptPathStopsOnPlainStopSequences() async throws {
        let s = try await load()
        let prompt = "Question: What is 2+2?\nAnswer: 4\nQuestion: What is 3+3?\nAnswer:"
        let c = try await collect(s.generate(GenerationRequest(
            prompt: prompt, sampling: Sampling(nPredict: 60, temperature: 0, stops: AnswerStopSequences.plain)
        )))
        let m = try #require(c.done.first)
        #expect(["stop", "eos"].contains(m.stopReason))
        #expect(!c.text.contains("Question:"))
        await s.close()
    }

    @Test func droppingTheStreamStopsNativeGeneration() async throws {
        let s = try await load()
        let begin = Date()
        let task = Task {
            for try await e in s.generate(GenerationRequest(messages: askQuestion, sampling: Sampling(nPredict: 5000, temperature: 0.7))) {
                if case .piece = e { break }  // leave after the first piece: onTermination(.cancelled)
            }
        }
        try await task.value
        // The next generation can only start once the abandoned one has stopped; 5000 tokens would take far longer than this.
        let c = try await collect(s.generate(GenerationRequest(messages: askQuestion, sampling: Sampling(nPredict: 2, temperature: 0))))
        #expect(c.done.first?.stopReason == "length")
        #expect(Date().timeIntervalSince(begin) < 30)
        await s.close()
    }

    @Test func benchRunsAShortPass() async throws {
        let s = try await load()
        let r = try await s.bench(nPp: 64, nTg: 8, reps: 1)
        #expect(r.pp != nil && r.tg != nil)
        #expect(r.nPp == 64 && r.nTg == 8)
        #expect(r.threads == threads)
        report(String(format: "bench pp64 %.1f tok/s, tg8 %.1f tok/s", r.pp?.mean ?? 0, r.tg?.mean ?? 0))
        await s.close()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BOAR_TEST_BENCH"] != nil))
    func benchLong() async throws {
        let s = try await load()
        let r = try await s.bench(nPp: 512, nTg: 64, reps: 2)
        report(String(format: "bench threads %d gpuLayers %d: pp512 %.1f tok/s (sd %.1f), tg64 %.1f tok/s (sd %.1f)",
                      threads, gpuLayers ?? LlamaSession.defaultGpuLayers, r.pp?.mean ?? 0, r.pp?.sd ?? 0, r.tg?.mean ?? 0, r.tg?.sd ?? 0))
        await s.close()
    }

    @Test func closedSessionThrowsNotLoaded() async throws {
        let s = try await load()
        await s.close()
        await s.close()  // idempotent
        await #expect(throws: ModelSeamError.notLoaded) {
            _ = try await collect(s.generate(GenerationRequest(messages: askQuestion)))
        }
    }

    @Test func embeddingsAreRejectedOnAChatSession() async throws {
        let s = try await load()
        await #expect(throws: ModelSeamError.self) { _ = try await s.embed("hello") }
        await s.close()
    }
}

@Suite("embedding model", .enabled(if: embedModelPath != nil))
struct Embedding {
    private func cosine(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
    private func norm(_ v: [Float]) -> Float { v.reduce(0) { $0 + $1 * $1 }.squareRoot() }

    @Test func embedsAndNormalizes() async throws {
        let t0 = Date()
        let e = try await LlamaSession.load(path: try #require(embedModelPath), params: .embedder)
        #expect(e.capabilities.hasChatTemplate == false)
        let n = try #require(e.dimensions)
        #expect(n == 384)

        let a = try await e.embed("How do I treat a minor burn?")
        let a2 = try await e.embed("How do I treat a minor burn?")
        let b = try await e.embed("First aid for small burns on the skin")
        let c = try await e.embed("The stock exchange closed higher on Tuesday")
        #expect(a.count == n)
        #expect(abs(norm(a) - 1) < 1e-3)
        #expect(a == a2)
        #expect(cosine(a, b) > cosine(a, c))
        let raw = try await e.embed("How do I treat a minor burn?", normalize: false)
        #expect(raw.count == n)
        #expect(abs(norm(raw) - 1) > 1e-3 || abs(norm(raw) - 1) < 1e-3)  // either is legal; just must be finite
        #expect(raw.allSatisfy { $0.isFinite })
        report(String(format: "embed: %d dims, 4 embeddings in %.2f s incl. load, cos(near) %.3f cos(far) %.3f",
                      n, Date().timeIntervalSince(t0), cosine(a, b), cosine(a, c)))

        // a chat request on an embedding session is a clear error, not a crash
        await #expect(throws: ModelSeamError.self) {
            _ = try await collect(e.generate(GenerationRequest(messages: askQuestion)))
        }
        await e.close()
        await #expect(throws: ModelSeamError.notLoaded) { _ = try await e.embed("x") }
    }
}
}
