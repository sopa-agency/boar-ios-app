import BoarCore
import Foundation
import llama

/// One loaded GGUF. Conforms to the model seam (`TextModelSession`, `RawPromptFormatting`, `BenchmarkableSession`) and, when
/// opened with `EngineParams.embeddings`, to `TextEmbedder` (the Kotlin `LlamaSession` did both).
///
/// Threading: every native call runs on one dedicated serial queue (`LlamaWorker`); calls are serialized. `cancel()` and `close()`
/// may be called from any thread.
public final class LlamaSession: TextModelSession, RawPromptFormatting, BenchmarkableSession, TextEmbedder {
    public let params: EngineParams
    public let info: ModelInfo
    public let capabilities: ModelCapabilities
    public var dimensions: Int? { params.embeddings ? embeddingDimensions : nil }

    private let embeddingDimensions: Int
    private let worker: LlamaWorker
    private let cancelFlag: StopFlag
    private let closing = StopFlag()

    private init(worker: LlamaWorker, cancelFlag: StopFlag, params: EngineParams, loaded: LlamaLoaded) {
        self.worker = worker
        self.cancelFlag = cancelFlag
        self.params = params
        self.info = loaded.info
        self.capabilities = loaded.capabilities
        self.embeddingDimensions = loaded.embeddingDimensions
    }

    // MARK: Loading

    /// Layers offloaded to Metal when `load` is not told otherwise: all of them where `metalEnabled`, else none.
    ///
    /// Android runs ggml's CPU backend with the per-device dotprod/i8mm/SVE kernels. On Apple silicon Metal is the fast path:
    /// measured with Qwen2.5-1.5B Q4_K_M, CPU-only (gpuLayers 0, 4 threads) gave 11 tok/s decode on a Mac mini M4 and Metal gave
    /// 54 tok/s there (91 tok/s on an M1 Pro). Pass 0 to force the CPU path (Android parity, memory-constrained devices).
    public static var defaultGpuLayers: Int { metalEnabled ? 999 : 0 }

    /// Metal on a Mac (BOAR_METAL=0 turns it off); CPU on iPhone and iPad (BOAR_METAL=1 turns Metal on) and in the Simulator.
    ///
    /// This llama.cpp build compiles ggml's Metal shader source at run time. On the 4 GB iPhone 13 that took up to three
    /// MTLCompilerService processes of ~470 MB each: the system thrashed (jetsam killed dozens of daemons, free memory fell to
    /// ~30 MB, the UI froze for everyone) and a pipeline that never compiled crashed the embedder in
    /// `ggml_metal_library_get_pipeline` (2026-10-16). Metal on iOS waits for a precompiled metallib.
    public static var metalEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["BOAR_METAL"]
        #if targetEnvironment(simulator)
        return false
        #elseif os(macOS)
        return env != "0"
        #else
        return env == "1"
        #endif
    }

    /// Loads a GGUF file (the Kotlin `LlamaSession.load`, which returned null on failure; this throws `LlamaError`).
    ///
    /// `gpuLayers`: layers kept on the GPU; nil = `defaultGpuLayers`, 0 = CPU only (Android parity).
    public static func load(path: String, params: EngineParams = EngineParams(), gpuLayers: Int? = nil) async throws -> LlamaSession {
        let worker = LlamaWorker()
        let cancel = StopFlag()
        let loaded = try await worker.load(path: path, params: params, gpuLayers: gpuLayers ?? defaultGpuLayers, sessionCancel: cancel)
        return LlamaSession(worker: worker, cancelFlag: cancel, params: params, loaded: loaded)
    }

    /// llama.cpp's own summary of the CPU/GPU features it found (Kotlin `BoarEngine.systemInfo`).
    public static func systemInfo() -> String {
        _ = LlamaBackend.ready
        return String(cString: llama_print_system_info())
    }

    // MARK: TextModelSession

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        let worker = worker, cancel = cancelFlag
        let run = RunControl(sessionCancel: cancel)
        let isClosing = closing.isSet
        return AsyncThrowingStream { continuation in
            if isClosing { continuation.finish(throwing: ModelSeamError.notLoaded); return }
            // A consumer that drops the stream (or cancels its task) stops the native generation.
            continuation.onTermination = { termination in
                if case .cancelled = termination { run.stop.set() }
            }
            Task { await worker.generate(request, sessionCancel: cancel, run: run, continuation: continuation) }
        }
    }

    public func cancel() { cancelFlag.set() }

    public func prewarm(_ input: GenerationRequest.Input, enableThinking: Bool) async {
        if closing.isSet { return }
        let run = RunControl(sessionCancel: cancelFlag)
        await worker.prewarm(input, enableThinking: enableThinking, sessionCancel: cancelFlag, run: run)
    }

    public func close() async {
        closing.set()
        cancelFlag.set()
        await worker.free()
    }

    // MARK: RawPromptFormatting / BenchmarkableSession

    public func formatChat(_ messages: [ChatMessage], enableThinking: Bool) async throws -> FormattedPrompt {
        try await worker.formatChat(messages, enableThinking: enableThinking)
    }

    public func bench(nPp: Int, nTg: Int, reps: Int) async throws -> BenchResult {
        if closing.isSet { throw ModelSeamError.notLoaded }
        return try await worker.bench(nPp: nPp, nTg: nTg, reps: reps, sessionCancel: cancelFlag, run: RunControl(sessionCancel: cancelFlag))
    }

    // MARK: TextEmbedder

    public func embed(_ text: String, normalize: Bool) async throws -> [Float] {
        if closing.isSet { throw ModelSeamError.notLoaded }
        return try await worker.embed(text, normalize: normalize, sessionCancel: cancelFlag, run: RunControl(sessionCancel: cancelFlag))
    }
}
