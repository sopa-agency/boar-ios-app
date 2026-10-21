// Core AI ships in the device SDKs only (no iOS Simulator slice): the adapter compiles where the module exists.
#if canImport(CoreAI)
import BoarCore
import CoreAI
import Foundation

/// iOS 27: a model compiled for Core AI (`.aimodel` asset), loaded from a URL, behind the BOAR model seam.
///
/// STATUS: documented stub for generation. The iOS 27 SDK's Core AI (`CoreAIRuntime`, `CoreAIAsset`, `CoreAIDelegates`) exposes
/// tensor-level inference only: `AIModel(contentsOf:)` / `AIModel.specialize(contentsOf:)`, `functionNames`,
/// `InferenceFunction` + `NDArray`. It has no language-model API (no tokenizer, chat template, sampler or KV cache), and the
/// Foundation Models `LanguageModel` / `LanguageModelExecutor` protocols would need all of those written by hand. So this adapter:
/// - loads and specializes the model (validating the file and warming the Core AI cache),
/// - reports what it is (`info`, `functionNames`, the asset's author / description metadata),
/// - throws `ModelSeamError.unsupportedInput` from `generate` until a tokenizer + decode loop over `InferenceFunction` lands.
/// The pipeline must keep using llama.cpp or `AppleSystemModel` for text.
@available(iOS 27, macOS 27, visionOS 27, *)
public final class CoreAIModelAdapter: TextModelSession, @unchecked Sendable {
    public static let backend = "apple-core-ai"
    public static let unsupportedMessage = "Core AI exposes tensor inference only; text generation over a Core AI model is not implemented"

    public let url: URL
    // Stored type-erased: a class whose stored property has a Core AI type can't be realized on an OS without CoreAI.framework
    // (the framework is weak-linked; runtime class enumeration — XCTest discovery, some SDKs — would crash on iOS/macOS 26).
    private let storage: any Sendable
    public var model: AIModel { storage as! AIModel }
    /// The model's inference functions (e.g. "prefill", "decode" for an exported LLM).
    public let functionNames: [String]
    public let author: String?
    public let modelDescription: String?

    private init(url: URL, model: AIModel, author: String?, modelDescription: String?) {
        self.url = url; self.storage = model; self.functionNames = model.functionNames
        self.author = author; self.modelDescription = modelDescription
    }

    /// Whether `url` holds a Core AI model asset.
    public static func isModelAsset(_ url: URL) -> Bool { AIModelAsset.isValid(at: url) }

    /// Loads (and specializes, through the shared Core AI cache) the model at `url`.
    public static func load(from url: URL) async throws -> CoreAIModelAdapter {
        let asset = AIModelAsset.isValid(at: url) ? (try? AIModelAsset(contentsOf: url)) : nil
        let metadata = asset?.metadata
        let model: AIModel
        do { model = try await AIModel.specialize(contentsOf: url) } catch {
            throw ModelSeamError.generationFailed("core ai load: \(error)")
        }
        return CoreAIModelAdapter(
            url: url, model: model, author: metadata.map(\.author).flatMap { $0.isEmpty ? nil : $0 },
            modelDescription: metadata.map(\.description).flatMap { $0.isEmpty ? nil : $0 })
    }

    public var info: ModelInfo {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
        return ModelInfo(name: url.lastPathComponent, backend: Self.backend, architecture: "core-ai", sizeBytes: size)
    }

    public var capabilities: ModelCapabilities {
        ModelCapabilities(hasChatTemplate: false, acceptsRawPrompt: false, supportsThinking: false, supportsPrewarm: false, contextTokens: nil)
    }

    public func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: ModelSeamError.unsupportedInput(Self.unsupportedMessage)) }
    }

    public func cancel() {}
    public func close() async {}
}
#endif
