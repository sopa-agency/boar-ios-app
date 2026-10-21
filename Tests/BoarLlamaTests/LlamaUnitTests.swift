import BoarCore
import Foundation
import Testing
import llama

@testable import BoarLlama

// Tests that need no model file.

private let chatML = #"{% for message in messages %}{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}{% endfor %}{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}"#
private let qwen3Hybrid = chatML + #"{%- if enable_thinking is defined and enable_thinking is false %}{{- '<think>\n\n</think>\n\n' }}{%- endif %}"#
private let qwen35Hybrid = chatML + #"{%- if enable_thinking is defined and enable_thinking is false %}{{- '<think>\n\n</think>\n\n' }}{%- else %}{{- '<think>\n' }}{%- endif %}"#
private let qwenAlwaysThinking = #"{% for message in messages %}{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}{% endfor %}{% if add_generation_prompt %}{{ '<|im_start|>assistant\n<think>\n' }}{% endif %}"#

private let sampleChat: [ChatMessage] = [
    ChatMessage(role: .system, content: "Be brief."),
    ChatMessage(role: .user, content: "Hi"),
]

@Suite("Llama support")
struct LlamaSupportTests {
    @Test func completeUTF8LengthMatchesKotlin() {
        #expect(completeUTF8Length([]) == 0)
        #expect(completeUTF8Length(Array("abc".utf8)) == 3)
        let euro = Array("€".utf8)  // E2 82 AC
        #expect(completeUTF8Length(euro) == 3)
        #expect(completeUTF8Length(Array(euro.dropLast())) == 0)
        #expect(completeUTF8Length(Array("a".utf8) + euro.dropLast(2)) == 1)
        let rocket = Array("🚀".utf8)  // 4 bytes
        #expect(completeUTF8Length(rocket) == 4)
        #expect(completeUTF8Length(Array(rocket.dropLast())) == 0)
        #expect(completeUTF8Length(Array("ab".utf8) + rocket.dropLast()) == 2)
    }

    @Test func mergedStopsKeepsOrderAndDropsDuplicates() {
        #expect(mergedStops(["<end>", "\nUser:"], ["\nUser:", "", "X"]) == ["<end>", "\nUser:", "X"])
        #expect(mergedStops([], []) == [])
    }

    @Test func stopFlagAndRunControl() {
        let session = StopFlag()
        let run = RunControl(sessionCancel: session)
        #expect(!run.shouldAbort)
        session.set()
        #expect(run.shouldAbort)
        session.clear()
        #expect(!run.shouldAbort)
        run.stop.set()
        #expect(run.shouldAbort)
        #expect(!session.isSet)
    }

    @Test func engineParamsMapToLlamaStructs() {
        let p = EngineParams(
            nCtx: 3000, nBatch: 256, nUbatch: 128, threads: 3, threadsBatch: 5, typeK: .q8_0, typeV: .q4_0, flashAttn: .on,
            loadMode: .mmapMlock, lazyMode: .auto, repack: false, embeddings: true
        )
        let mp = LlamaParamMapping.modelParams(p, gpuLayers: 7)
        #expect(mp.n_gpu_layers == 7)
        #expect(mp.load_mode == LLAMA_LOAD_MODE_MMAP_MLOCK)
        #expect(mp.lazy_mode == LLAMA_LAZY_MODE_AUTO)
        #expect(mp.use_extra_bufts == false)

        let cp = LlamaParamMapping.contextParams(p)
        #expect(cp.n_ctx == 3000)
        #expect(cp.n_batch == 256)
        #expect(cp.n_ubatch == 128)
        #expect(cp.n_threads == 3)
        #expect(cp.n_threads_batch == 5)
        #expect(cp.type_k == GGML_TYPE_Q8_0)
        #expect(cp.type_v == GGML_TYPE_Q4_0)
        #expect(cp.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_ENABLED)
        #expect(cp.embeddings == true)
        #expect(cp.no_perf == false)

        let d = LlamaParamMapping.modelParams(EngineParams(), gpuLayers: 0)
        #expect(d.load_mode == LLAMA_LOAD_MODE_MMAP)
        #expect(d.lazy_mode == LLAMA_LAZY_MODE_OFF)
        #expect(d.use_extra_bufts == true)
        let dc = LlamaParamMapping.contextParams(EngineParams())
        #expect(dc.type_k == GGML_TYPE_F16)
        #expect(dc.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_AUTO)
        #expect(LlamaParamMapping.contextParams(EngineParams.embedder).n_ctx == 512)
    }

    @Test func samplerSeed() {
        #expect(LlamaParamMapping.samplerSeed(-1) == UInt32.max)
        #expect(LlamaParamMapping.samplerSeed(42) == 42)
        #expect(LlamaParamMapping.samplerSeed(0) == 0)
    }

    @Test func backendReportsSystemInfo() {
        #expect(!LlamaSession.systemInfo().isEmpty)
    }
}

@Suite("Llama chat template")
struct LlamaChatTemplateTests {
    @Test func chatMLRendersLikeTheQwenTemplate() throws {
        let t = try #require(LlamaChatTemplate.make(source: chatML))
        let f = try t.format(sampleChat, enableThinking: false)
        #expect(f.prompt == "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n")
        #expect(f.supportsThinking == false)
        #expect(f.thinkingStart == "")
        #expect(f.thinkingEnd.isEmpty)
        #expect(f.stops.isEmpty)
    }

    @Test func multiTurnHistoryAndUnicodeSurvive() throws {
        let t = try #require(LlamaChatTemplate.make(source: chatML))
        let msgs = sampleChat + [
            ChatMessage(role: .assistant, content: "Olá 🚀"),
            ChatMessage(role: .user, content: "Mais: é à ç"),
        ]
        let p = try t.apply(msgs)
        #expect(p.contains("<|im_start|>assistant\nOlá 🚀<|im_end|>\n"))
        #expect(p.hasSuffix("<|im_start|>user\nMais: é à ç<|im_end|>\n<|im_start|>assistant\n"))
    }

    @Test func longMessagesGrowTheBuffer() throws {
        let t = try #require(LlamaChatTemplate.make(source: chatML))
        let long = String(repeating: "x", count: 50_000)
        let p = try t.apply([ChatMessage(role: .user, content: long)])
        #expect(p.count == "<|im_start|>user\n".count + 50_000 + "<|im_end|>\n<|im_start|>assistant\n".count)
    }

    @Test func qwen3HybridSwitchesThinkingWithAnEmptyBlock() throws {
        let t = try #require(LlamaChatTemplate.make(source: qwen3Hybrid))
        #expect(t.supportsThinking)
        let off = try t.format(sampleChat, enableThinking: false)
        #expect(off.prompt.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"))
        #expect(off.supportsThinking)
        #expect(off.thinkingStart == "<think>")
        #expect(off.thinkingEnd == ["</think>"])
        let on = try t.format(sampleChat, enableThinking: true)
        #expect(on.prompt.hasSuffix("<|im_start|>assistant\n"))
    }

    @Test func qwen35OpensTheThinkBlockWhenEnabled() throws {
        let t = try #require(LlamaChatTemplate.make(source: qwen35Hybrid))
        let on = try t.format(sampleChat, enableThinking: true)
        #expect(on.prompt.hasSuffix("<|im_start|>assistant\n<think>\n"))
        let off = try t.format(sampleChat, enableThinking: false)
        #expect(off.prompt.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    }

    @Test func alwaysThinkingVariantCannotBeSwitchedOff() throws {
        let t = try #require(LlamaChatTemplate.make(source: qwenAlwaysThinking))
        #expect(t.supportsThinking == false)
        for flag in [false, true] {
            let f = try t.format(sampleChat, enableThinking: flag)
            #expect(f.prompt.hasSuffix("<|im_start|>assistant\n<think>\n"))
            #expect(f.thinkingEnd == ["</think>"])
        }
    }

    @Test func unknownOrEmptyTemplatesAreRejected() {
        #expect(LlamaChatTemplate.make(source: nil) == nil)
        #expect(LlamaChatTemplate.make(source: "") == nil)
        #expect(LlamaChatTemplate.make(source: "{{ nothing we recognise }}") == nil)
    }
}

@Suite("Llama loading")
struct LlamaLoadingTests {
    @Test func missingFileThrows() async {
        let path = "/nonexistent/boar-test.gguf"
        await #expect(throws: LlamaError.fileNotFound(path)) {
            _ = try await LlamaSession.load(path: path)
        }
    }

    @Test func notAGGUFThrows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boar-not-a-model-\(UUID().uuidString).gguf")
        try Data("this is not a gguf file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: LlamaError.loadFailed(url.path)) {
            _ = try await LlamaSession.load(path: url.path)
        }
    }
}
