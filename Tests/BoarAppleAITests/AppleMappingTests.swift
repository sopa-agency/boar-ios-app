import BoarCore
import Foundation
import FoundationModels
import Testing
@testable import BoarAppleAI

@Suite struct PromptPlanTests {
    @Test func systemAndUser() throws {
        let plan = try ApplePromptPlan.make([ChatMessage(role: .system, content: "Be brief."), ChatMessage(role: .user, content: "Hi?")])
        #expect(plan == ApplePromptPlan(instructions: "Be brief.", history: [], prompt: "Hi?"))
    }

    @Test func multiTurnHistory() throws {
        let plan = try ApplePromptPlan.make([
            ChatMessage(role: .system, content: "S"),
            ChatMessage(role: .user, content: "q1"),
            ChatMessage(role: .assistant, content: "a1"),
            ChatMessage(role: .user, content: "q2"),
        ])
        #expect(plan.instructions == "S")
        #expect(plan.history == [.user("q1"), .assistant("a1")])
        #expect(plan.prompt == "q2")
    }

    @Test func noSystemMeansNoInstructions() throws {
        let plan = try ApplePromptPlan.make([ChatMessage(role: .user, content: "q")])
        #expect(plan.instructions == nil)
    }

    @Test func laterSystemMessagesAppendToInstructions() throws {
        let plan = try ApplePromptPlan.make([
            ChatMessage(role: .system, content: "A"), ChatMessage(role: .user, content: "q1"),
            ChatMessage(role: .system, content: "B"), ChatMessage(role: .user, content: "q2"),
        ])
        #expect(plan.instructions == "A\n\nB")
        #expect(plan.history == [.user("q1")])
        #expect(plan.prompt == "q2")
    }

    @Test func trailingSystemIsAllowed() throws {
        let plan = try ApplePromptPlan.make([ChatMessage(role: .user, content: "q"), ChatMessage(role: .system, content: "S")])
        #expect(plan.instructions == "S")
        #expect(plan.prompt == "q")
    }

    @Test func rejectsRawPromptNoUserAndPrefill() {
        #expect(throws: ModelSeamError.self) { try ApplePromptPlan.make(.prompt("x")) }
        #expect(throws: ModelSeamError.unsupportedInput("no user message")) {
            try ApplePromptPlan.make([ChatMessage(role: .system, content: "S")])
        }
        #expect(throws: ModelSeamError.unsupportedInput("assistant prefill after the last user message")) {
            try ApplePromptPlan.make([ChatMessage(role: .user, content: "q"), ChatMessage(role: .assistant, content: "The answer is")])
        }
    }

    @Test func rawPromptErrorIsUnsupportedInput() {
        do {
            _ = try ApplePromptPlan.make(.prompt("x"))
            Issue.record("expected a throw")
        } catch let e as ModelSeamError {
            guard case .unsupportedInput = e else { Issue.record("wrong case \(e)"); return }
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func prefixKeyIgnoresPromptOnly() throws {
        let a = try ApplePromptPlan.make([ChatMessage(role: .system, content: "S"), ChatMessage(role: .user, content: "one")])
        let b = try ApplePromptPlan.make([ChatMessage(role: .system, content: "S"), ChatMessage(role: .user, content: "two")])
        let c = try ApplePromptPlan.make([ChatMessage(role: .system, content: "T"), ChatMessage(role: .user, content: "one")])
        #expect(a.prefixKey == b.prefixKey)
        #expect(a.prefixKey != c.prefixKey)
    }
}

@Suite struct OptionsPlanTests {
    @Test func defaultsMapToNucleus() {
        let plan = AppleOptionsPlan.make(Sampling())
        #expect(plan == AppleOptionsPlan(sampling: .nucleus(threshold: Double(Float(0.95)), seed: nil),
                                         temperature: Double(Float(0.7)), maximumResponseTokens: 512))
    }

    @Test func zeroTemperatureIsGreedy() {
        let plan = AppleOptionsPlan.make(Sampling(nPredict: 64, temperature: 0))
        #expect(plan == AppleOptionsPlan(sampling: .greedy, temperature: nil, maximumResponseTokens: 64))
    }

    @Test func seedAppliesWithoutTopP() {
        #expect(AppleOptionsPlan.make(Sampling(topP: 1, seed: 42)).sampling == .nucleus(threshold: 1, seed: 42))
        #expect(AppleOptionsPlan.make(Sampling(topP: 1, seed: -1)).sampling == .systemDefault)
        #expect(AppleOptionsPlan.make(Sampling(topP: 0.9, seed: 7)).sampling == .nucleus(threshold: Double(Float(0.9)), seed: 7))
    }

    @Test func prefillOnlyHasNoCap() {
        #expect(AppleOptionsPlan.make(Sampling(nPredict: 0)).maximumResponseTokens == nil)
    }

    @Test func ignoresLlamaOnlyKnobs() {
        let a = AppleOptionsPlan.make(Sampling(topK: 40, minP: 0.05, repeatPenalty: 1.0))
        let b = AppleOptionsPlan.make(Sampling(topK: 1, minP: 0.5, repeatPenalty: 1.3))
        #expect(a == b)
    }

    @Test func foundationModelsOptions() {
        let options = AppleOptionsPlan.make(Sampling(nPredict: 128, temperature: 0.5, topP: 0.8, seed: 3)).generationOptions
        #expect(options == GenerationOptions(samplingMode: .random(probabilityThreshold: Double(Float(0.8)), seed: 3),
                                             temperature: Double(Float(0.5)), maximumResponseTokens: 128))
        let greedy = AppleOptionsPlan.make(Sampling(temperature: 0)).generationOptions
        #expect(greedy == GenerationOptions(samplingMode: .greedy, temperature: nil, maximumResponseTokens: 512))
        let system = AppleOptionsPlan.make(Sampling(topP: 1)).generationOptions
        #expect(system.samplingMode == nil)
    }
}

@Suite struct StreamHelpersTests {
    @Test func snapshotDeltas() {
        var d = SnapshotDiffer()
        #expect(d.delta("Hel") == "Hel")
        #expect(d.delta("Hello") == "lo")
        #expect(d.delta("Hello") == "")
        #expect(d.delta("Hello, world") == ", world")
    }

    @Test func snapshotRewriteEmitsOnlyNewLength() {
        var d = SnapshotDiffer()
        _ = d.delta("abc")
        #expect(d.delta("abX de") == " de")
        #expect(d.delta("ab") == "")
        #expect(d.delta("abX def") == "f")
    }

    @Test func stopReasons() {
        #expect(AppleStopReason.derive(hitStop: true, cancelled: true, generatedTokens: 5, maximumResponseTokens: 5) == "stop")
        #expect(AppleStopReason.derive(hitStop: false, cancelled: true, generatedTokens: 5, maximumResponseTokens: 5) == "cancelled")
        #expect(AppleStopReason.derive(hitStop: false, cancelled: false, generatedTokens: 5, maximumResponseTokens: 5) == "length")
        #expect(AppleStopReason.derive(hitStop: false, cancelled: false, generatedTokens: 4, maximumResponseTokens: 5) == "eos")
        #expect(AppleStopReason.derive(hitStop: false, cancelled: false, generatedTokens: 0, maximumResponseTokens: 5) == "eos")
        #expect(AppleStopReason.derive(hitStop: false, cancelled: false, generatedTokens: 9, maximumResponseTokens: nil) == "eos")
    }
}

@Suite struct ErrorMappingTests {
    @available(macOS, deprecated: 27.0)
    @Test func legacyGenerationErrors() {
        let ctx = LanguageModelSession.GenerationError.Context(debugDescription: "blocked")
        let guardrail = AppleAIErrorMapping.map(LanguageModelSession.GenerationError.guardrailViolation(ctx))
        #expect(AppleAIFailure.of(guardrail) == .guardrailViolation)
        #expect(AppleAIFailure.of(guardrail)?.isSafetyBlock == true)

        let refusal = AppleAIErrorMapping.map(LanguageModelSession.GenerationError.refusal(.init(transcriptEntries: []), ctx))
        #expect(AppleAIFailure.of(refusal) == .refusal)
        #expect(AppleAIFailure.of(refusal)?.isSafetyBlock == true)

        let context = AppleAIErrorMapping.map(LanguageModelSession.GenerationError.exceededContextWindowSize(ctx))
        #expect(AppleAIFailure.of(context) == .contextWindowExceeded)
        #expect(AppleAIFailure.of(context)?.isSafetyBlock == false)

        #expect(AppleAIFailure.of(AppleAIErrorMapping.map(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(ctx))) == .unsupportedLanguage)
        #expect(AppleAIFailure.of(AppleAIErrorMapping.map(LanguageModelSession.GenerationError.rateLimited(ctx))) == .rateLimited)
        #expect(AppleAIFailure.of(AppleAIErrorMapping.map(LanguageModelSession.GenerationError.assetsUnavailable(ctx))) == .assetsUnavailable)
    }

    @Test func languageModelErrorsOnIOS27() throws {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }  // host runtime older than 27: nothing to map
        let g = AppleAIErrorMapping.map(LanguageModelError.guardrailViolation(.init(debugDescription: "x")))
        #expect(AppleAIFailure.of(g) == .guardrailViolation)
        let c = AppleAIErrorMapping.map(LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")))
        #expect(AppleAIFailure.of(c) == .contextWindowExceeded)
    }

    struct Unrelated: Error {}

    @Test func unrelatedAndSeamErrors() {
        #expect(AppleAIFailure.of(AppleAIErrorMapping.map(Unrelated())) == .other)
        #expect(AppleAIErrorMapping.map(ModelSeamError.notLoaded) == .notLoaded)
        #expect(AppleAIFailure.of(ModelSeamError.notLoaded) == nil)
        #expect(AppleAIFailure.of(ModelSeamError.generationFailed("decode failed")) == nil)
        #expect(AppleAIFailure.of(ModelSeamError.generationFailed("refusal")) == .refusal)
        #expect(AppleAIFailure.of(ModelSeamError.generationFailed("model unavailable: modelNotReady")) == .unavailable)
        #expect(AppleAIFailure.of(Unrelated()) == nil)
    }

    @Test func seamErrorMessageFormat() {
        #expect(AppleAIFailure.guardrailViolation.seamError("nope") == .generationFailed("guardrail violation: nope"))
        #expect(AppleAIFailure.refusal.seamError("") == .generationFailed("refusal"))
    }
}

@Suite struct AvailabilityTests {
    @Test func mapsReasons() {
        #expect(AppleModelAvailability(SystemLanguageModel.Availability.available) == .available)
        #expect(AppleModelAvailability(SystemLanguageModel.Availability.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AppleModelAvailability(SystemLanguageModel.Availability.unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceNotEnabled)
        #expect(AppleModelAvailability(SystemLanguageModel.Availability.unavailable(.modelNotReady)) == .modelNotReady)
    }

    @Test func transientAndMessages() {
        #expect(!AppleModelAvailability.deviceNotEligible.isTransient)
        #expect(AppleModelAvailability.modelNotReady.isTransient)
        #expect(AppleModelAvailability.appleIntelligenceNotEnabled.userMessage.contains("Settings"))
        #expect(AppleModelAvailability.available.isAvailable)
        #expect(AppleModelAvailability.deviceNotEligible.code == "deviceNotEligible")
    }

    @Test func currentIsReadable() {
        let current = AppleModelAvailability.current
        BoarLog.logger("AppleAITests").info("host availability: \(current.code, privacy: .public)")
        #expect(!current.code.isEmpty)
    }
}
