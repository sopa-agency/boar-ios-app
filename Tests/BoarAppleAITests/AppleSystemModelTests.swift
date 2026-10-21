import BoarCore
import Foundation
import FoundationModels
import Testing
@testable import BoarAppleAI

private let modelAvailable = AppleModelAvailability.current.isAvailable

@Suite struct AppleSystemModelTests {
    @Test func capabilitiesAndInfo() {
        let m = AppleSystemModel()
        #expect(m.capabilities.hasChatTemplate)
        #expect(!m.capabilities.acceptsRawPrompt)
        #expect(!m.capabilities.supportsThinking)
        #expect(m.capabilities.supportsPrewarm)
        #expect(m.capabilities.contextTokens == m.contextSize)
        #expect(m.contextSize > 0)
        #expect(m.info.backend == "apple-foundation-models")
        #expect(m.info.trainingContextTokens == m.contextSize)
    }

    @Test func transcriptMapping() throws {
        let m = AppleSystemModel()
        let plan = try ApplePromptPlan.make([
            ChatMessage(role: .system, content: "S"), ChatMessage(role: .user, content: "q1"),
            ChatMessage(role: .assistant, content: "a1"), ChatMessage(role: .user, content: "q2"),
        ])
        let entries = Array(m.transcript(for: plan))
        #expect(entries.count == 3)
        guard entries.count == 3 else { return }
        guard case .instructions(let i) = entries[0], case .text(let iText) = i.segments.first else { Issue.record("instructions"); return }
        #expect(iText.content == "S")
        #expect(i.toolDefinitions.isEmpty)
        guard case .prompt(let p) = entries[1], case .text(let pText) = p.segments.first else { Issue.record("prompt"); return }
        #expect(pText.content == "q1")
        guard case .response(let r) = entries[2], case .text(let rText) = r.segments.first else { Issue.record("response"); return }
        #expect(rText.content == "a1")
    }

    @Test func noInstructionsNoEntry() throws {
        let m = AppleSystemModel()
        let entries = Array(m.transcript(for: try ApplePromptPlan.make([ChatMessage(role: .user, content: "q")])))
        #expect(entries.isEmpty)
    }

    @Test func rawPromptIsRejectedFromTheStream() async {
        let m = AppleSystemModel()
        do {
            for try await _ in m.generate(GenerationRequest(prompt: "Question: hi\nAnswer:")) {}
            Issue.record("expected a throw")
        } catch let e as ModelSeamError {
            guard case .unsupportedInput = e else { Issue.record("wrong case \(e)"); return }
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func closedSessionThrowsNotLoaded() async {
        let m = AppleSystemModel()
        await m.close()
        await #expect(throws: ModelSeamError.notLoaded) {
            for try await _ in m.generate(GenerationRequest(messages: [ChatMessage(role: .user, content: "hi")])) {}
        }
    }

    @Test(.enabled(if: !modelAvailable)) func unavailableModelSurfacesReason() async {
        let m = AppleSystemModel()
        do {
            for try await _ in m.generate(GenerationRequest(messages: [ChatMessage(role: .user, content: "hi")])) {}
            Issue.record("expected a throw")
        } catch {
            #expect(AppleAIFailure.of(error) == .unavailable)
        }
    }

    @Test func cancelWhenIdleIsANoOp() {
        AppleSystemModel().cancel()
    }
}

/// Real model runs; skipped when Apple Intelligence isn't available on the host.
@Suite(.enabled(if: modelAvailable), .serialized) struct AppleSystemModelLiveTests {
    func collect(_ m: AppleSystemModel, _ r: GenerationRequest) async throws -> (text: String, dones: [GenerationMetrics]) {
        var text = "", dones: [GenerationMetrics] = []
        for try await e in m.generate(r) {
            switch e {
            case .piece(let p): #expect(!p.isEmpty); text += p
            case .done(let d): dones.append(d)
            }
        }
        return (text, dones)
    }

    @Test func generatesAndEndsWithOneDone() async throws {
        let m = AppleSystemModel()
        let r = GenerationRequest(messages: [ChatMessage(role: .system, content: "Answer in one short sentence."),
                                             ChatMessage(role: .user, content: "What is the capital of France?")],
                                  sampling: Sampling(nPredict: 48, temperature: 0))
        let (text, dones) = try await collect(m, r)
        #expect(!text.isEmpty)
        #expect(dones.count == 1)
        #expect(["eos", "length"].contains(dones.first?.stopReason ?? ""))
        await m.close()
    }

    @Test func honoursStops() async throws {
        let m = AppleSystemModel()
        let r = GenerationRequest(messages: [ChatMessage(role: .user, content: "Count from 1 to 10 separated by commas.")],
                                  sampling: Sampling(nPredict: 64, temperature: 0, stops: ["4"]))
        let (text, dones) = try await collect(m, r)
        #expect(!text.contains("4"))
        #expect(dones.first?.stopReason == "stop")
    }

    @Test func cancelKeepsTextAndReportsCancelled() async throws {
        let m = AppleSystemModel()
        let r = GenerationRequest(messages: [ChatMessage(role: .user, content: "Write a long essay about rivers.")],
                                  sampling: Sampling(nPredict: 1000))
        let out = try await m.generateText(r, timeout: .milliseconds(1500))
        #expect(out.timedOut)
        #expect(out.metrics?.stopReason == "cancelled")
    }
}
