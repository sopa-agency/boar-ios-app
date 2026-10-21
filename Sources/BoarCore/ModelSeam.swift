import Foundation

// MARK: - The model seam
//
// The answer pipeline, Deep Research, the plan executor and the chat layer talk to a language model only through these
// types. `BoarLlama` (llama.cpp over the C API) and `BoarAppleAI` (Foundation Models) both implement them.
//
// Level of the seam: MESSAGES. A request carries `[ChatMessage]` (system / user / assistant turns); the implementation
// renders them with the model's own template (llama.cpp `formatChat`) or hands them to the system model as instructions +
// transcript (Foundation Models). A raw prompt string is an optional second input, for a GGUF that ships no chat template
// (the hand-built prompt with stop words); `ModelCapabilities.acceptsRawPrompt` says whether an implementation takes it.
//
// The Kotlin `LlamaSession` call sequence `formatChat` → `generate(prompt)` collapses into one `generate(request)`.
// The rendered prompt is still reachable on llama through `RawPromptFormatting` (benchmarks, debugging).

/// What a loaded model is.
public struct ModelInfo: Sendable, Equatable {
    /// A display or file name (the GGUF's file name; "Apple on-device model").
    public var name: String
    /// "llama.cpp" or "apple-foundation-models".
    public var backend: String
    public var architecture: String?
    public var sizeBytes: Int64?
    public var parameterCount: Int64?
    public var trainingContextTokens: Int?
    public var embeddingDimensions: Int?

    public init(
        name: String, backend: String, architecture: String? = nil, sizeBytes: Int64? = nil, parameterCount: Int64? = nil,
        trainingContextTokens: Int? = nil, embeddingDimensions: Int? = nil
    ) {
        self.name = name; self.backend = backend; self.architecture = architecture; self.sizeBytes = sizeBytes
        self.parameterCount = parameterCount; self.trainingContextTokens = trainingContextTokens
        self.embeddingDimensions = embeddingDimensions
    }
}

/// What a session can do. Pipelines branch on these, never on the backend's name.
public struct ModelCapabilities: Sendable, Equatable {
    /// The model formats `.messages` itself (Kotlin `info.hasChatTemplate`). When false the pipeline must send a hand-built
    /// `.prompt` with `AnswerStopSequences.plain` (a GGUF without a template). Apple's model: always true.
    public var hasChatTemplate: Bool
    /// `.prompt` input is accepted. Apple's model: false (a request with `.prompt` throws `ModelSeamError.unsupportedInput`).
    public var acceptsRawPrompt: Bool
    /// The model can reason before answering (`GenerationRequest.enableThinking` has an effect).
    public var supportsThinking: Bool
    /// `prewarm` does something (a KV prefix reuse, or Foundation Models `prewarm`).
    public var supportsPrewarm: Bool
    /// The context window the session was opened with, in tokens. Sizes Auto answer length (`AppSettings.answerTokens`). nil = unknown.
    public var contextTokens: Int?

    public init(hasChatTemplate: Bool, acceptsRawPrompt: Bool, supportsThinking: Bool = false, supportsPrewarm: Bool = false, contextTokens: Int? = nil) {
        self.hasChatTemplate = hasChatTemplate; self.acceptsRawPrompt = acceptsRawPrompt
        self.supportsThinking = supportsThinking; self.supportsPrewarm = supportsPrewarm; self.contextTokens = contextTokens
    }
}

/// Turn ends for the hand-built prompt only (src/inference/LlamaEngine.ts DEFAULT_STOP_SEQUENCES).
public enum AnswerStopSequences {
    public static let plain = ["\nUser:", "\n\nUser:", "\nQuestion:", "\n\nQuestion:"]
}

/// One generation.
public struct GenerationRequest: Sendable, Equatable {
    public enum Input: Sendable, Equatable {
        /// Role messages. The first `system` message is the instructions; earlier turns are history.
        case messages([ChatMessage])
        /// A finished prompt string (templates-less GGUF only).
        case prompt(String)
    }

    public var input: Input
    public var sampling: Sampling
    /// The user's thinking tweak (`EngineTweaks.thinking`); off by default. Ignored by models that can't think.
    public var enableThinking: Bool

    public init(input: Input, sampling: Sampling = Sampling(), enableThinking: Bool = false) {
        self.input = input; self.sampling = sampling; self.enableThinking = enableThinking
    }
    public init(messages: [ChatMessage], sampling: Sampling = Sampling(), enableThinking: Bool = false) {
        self.init(input: .messages(messages), sampling: sampling, enableThinking: enableThinking)
    }
    public init(prompt: String, sampling: Sampling = Sampling(), enableThinking: Bool = false) {
        self.init(input: .prompt(prompt), sampling: sampling, enableThinking: enableThinking)
    }
}

public enum ModelSeamError: Error, Equatable, CustomStringConvertible {
    /// The request's input kind isn't supported by this model (`.prompt` on a messages-only model).
    case unsupportedInput(String)
    /// The model's chat template failed ("chat template: …").
    case chatTemplate(String)
    /// The session was closed or never loaded.
    case notLoaded
    /// The backend failed mid-generation (decode failure, system model refused, guardrail).
    case generationFailed(String)

    public var description: String {
        switch self {
        case .unsupportedInput(let s): "unsupported input: \(s)"
        case .chatTemplate(let s): "chat template: \(s)"
        case .notLoaded: "model not loaded"
        case .generationFailed(let s): "generation failed: \(s)"
        }
    }
}

/// One loaded language model. Implementations are `Sendable` (actor or lock-protected final class) and SERIALIZE calls: a
/// second `generate` waits for the first, because llama.cpp contexts are not thread-safe.
///
/// Stream contract for `generate`:
/// - yields `.piece` zero or more times (text deltas, never empty), then exactly one `.done(metrics)`, then finishes;
/// - `Sampling.stops` are honoured by every implementation (a chat-template model also stops on the template's own turn ends);
///   the stop text itself is not emitted and `metrics.stopReason == "stop"`;
/// - `cancel()` ends a generation in flight WITHOUT throwing: the stream still delivers `.done` with `stopReason == "cancelled"`,
///   and what was written is kept (the time limit relies on this);
/// - the consumer dropping or cancelling its task terminates the stream and stops the native generation (`onTermination`);
/// - failures (`ModelSeamError`) are thrown from the stream.
public protocol TextModelSession: Sendable {
    var info: ModelInfo { get }
    var capabilities: ModelCapabilities { get }

    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>

    /// Stops the generation in flight (any thread). A no-op when idle. A `cancel()` before a generation starts is lost.
    func cancel()

    /// Reads `input` into the model's cache without generating (the KV prefix after a title or summary left its own prompt there;
    /// Foundation Models `prewarm(promptPrefix:)`). Best effort; a no-op by default.
    func prewarm(_ input: GenerationRequest.Input, enableThinking: Bool) async

    /// Cancels, waits for the running call to return, then frees the model. Idempotent. The session is unusable afterwards.
    func close() async
}

extension TextModelSession {
    public func prewarm(_ input: GenerationRequest.Input, enableThinking: Bool) async {}
}

/// llama.cpp only: the rendered chat prompt, for benchmarks and diagnostics (Kotlin `formatChat`).
public protocol RawPromptFormatting: TextModelSession {
    func formatChat(_ messages: [ChatMessage], enableThinking: Bool) async throws -> FormattedPrompt
}

/// llama.cpp only: the pp/tg benchmark (Kotlin `bench`).
public protocol BenchmarkableSession: TextModelSession {
    func bench(nPp: Int, nTg: Int, reps: Int) async throws -> BenchResult
}

/// An embedding model (Kotlin: a `LlamaSession` opened with `embeddings = true`). Vectors must be from the same model that built
/// the knowledge packs (the packs' embedding sha), so the Apple NL embedder cannot stand in for the bundled BGE.
public protocol TextEmbedder: Sendable {
    /// Vector length, when known.
    var dimensions: Int? { get }
    /// Calls are serialized. `normalize` L2-normalizes the vector.
    func embed(_ text: String, normalize: Bool) async throws -> [Float]
    func close() async
}

extension TextEmbedder {
    public func embed(_ text: String) async throws -> [Float] { try await embed(text, normalize: true) }
}

/// "No embedding model installed": the empty vector the Kotlin `BoarServices.embed` returns, which retrieval treats as "no vector search".
public struct NullEmbedder: TextEmbedder {
    public init() {}
    public var dimensions: Int? { nil }
    public func embed(_ text: String, normalize: Bool) async throws -> [Float] { [] }
    public func close() async {}
}
