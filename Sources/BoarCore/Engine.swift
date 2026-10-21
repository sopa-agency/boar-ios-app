import Foundation

/// KV-cache element types, as ggml numbers them (`ggml_type`). JSON name = the Kotlin enum name (persisted by `EngineTweaks`).
public enum KvType: String, Codable, Sendable, CaseIterable {
    case f16 = "F16", q8_0 = "Q8_0", q4_0 = "Q4_0"
    public var ggml: Int {
        switch self { case .f16: 1; case .q8_0: 8; case .q4_0: 2 }
    }
}

/// `llama_flash_attn_type`.
public enum FlashAttn: String, Codable, Sendable, CaseIterable {
    case auto = "AUTO", off = "OFF", on = "ON"
    public var code: Int {
        switch self { case .auto: -1; case .off: 0; case .on: 1 }
    }
}

/// How weights are read: memory-mapped, mapped and locked in RAM, or read into memory (Kotlin `LoadMode.NONE`).
/// `.readAll` is named so it never collides with `Optional.none`.
public enum LoadMode: String, Codable, Sendable, CaseIterable {
    case mmap = "MMAP", mmapMlock = "MMAP_MLOCK", readAll = "NONE"
    public var code: Int {
        switch self { case .mmap: 1; case .mmapMlock: 3; case .readAll: 0 }
    }
}

/// MoE expert streaming (`llama_lazy_mode`).
public enum LazyMode: String, Codable, Sendable, CaseIterable {
    case off = "OFF", auto = "AUTO", on = "ON"
    public var code: Int {
        switch self { case .off: 0; case .auto: 1; case .on: 2 }
    }
}

/// Everything the Benchmark Sandbox can change. Defaults match what the Expo app ran with (llama.rn, 4 threads).
public struct EngineParams: Sendable, Equatable {
    public var nCtx: Int
    public var nBatch: Int
    public var nUbatch: Int
    public var threads: Int
    public var threadsBatch: Int
    /// CPU list like "4,5,6,7" (empty = let the OS place threads). Darwin has no thread affinity: informational on iOS.
    public var cpus: String
    public var strictCpu: Bool
    public var typeK: KvType
    public var typeV: KvType
    public var flashAttn: FlashAttn
    public var loadMode: LoadMode
    public var lazyMode: LazyMode
    /// Repack weights for the fast ARM kernels (in app memory); false reads them from the mapped file, about 2x slower prompts.
    public var repack: Bool
    public var embeddings: Bool
    /// Override the GGUF's chat template (empty = the model's own).
    public var chatTemplate: String

    public init(
        nCtx: Int = 4096, nBatch: Int = 512, nUbatch: Int = 512, threads: Int = 4, threadsBatch: Int? = nil,
        cpus: String = "", strictCpu: Bool = false, typeK: KvType = .f16, typeV: KvType = .f16,
        flashAttn: FlashAttn = .auto, loadMode: LoadMode = .mmap, lazyMode: LazyMode = .off, repack: Bool = true,
        embeddings: Bool = false, chatTemplate: String = ""
    ) {
        self.nCtx = nCtx; self.nBatch = nBatch; self.nUbatch = nUbatch; self.threads = threads
        self.threadsBatch = threadsBatch ?? threads
        self.cpus = cpus; self.strictCpu = strictCpu; self.typeK = typeK; self.typeV = typeV
        self.flashAttn = flashAttn; self.loadMode = loadMode; self.lazyMode = lazyMode; self.repack = repack
        self.embeddings = embeddings; self.chatTemplate = chatTemplate
    }

    /// The parameters of the embedding model the app loads (nCtx 512, 2 threads, embeddings on).
    public static let embedder = EngineParams(nCtx: 512, threads: 2, embeddings: true)

    /// Same keys as the Kotlin `toJson` (diagnostics, bench exports).
    public var json: JSONValue {
        .object([
            "nCtx": JSONValue(nCtx), "nBatch": JSONValue(nBatch), "nUbatch": JSONValue(nUbatch),
            "threads": JSONValue(threads), "threadsBatch": JSONValue(threadsBatch),
            "cpus": .string(cpus), "strictCpu": .bool(strictCpu),
            "typeK": JSONValue(typeK.ggml), "typeV": JSONValue(typeV.ggml), "flashAttn": JSONValue(flashAttn.code),
            "loadMode": JSONValue(loadMode.code), "lazyMode": JSONValue(lazyMode.code), "repack": .bool(repack),
            "embeddings": .bool(embeddings), "chatTemplate": .string(chatTemplate),
        ])
    }
    public func toJSON() -> String { json.jsonString }
}

public struct Sampling: Sendable, Equatable {
    public var nPredict: Int
    public var temperature: Float
    public var topK: Int
    public var topP: Float
    public var minP: Float
    public var repeatPenalty: Float
    /// Negative = random.
    public var seed: Int
    /// Extra stop strings. A chat-template model also stops on the template's own turn ends.
    public var stops: [String]

    public init(
        nPredict: Int = 512, temperature: Float = 0.7, topK: Int = 40, topP: Float = 0.95, minP: Float = 0.05,
        repeatPenalty: Float = 1.0, seed: Int = -1, stops: [String] = []
    ) {
        self.nPredict = nPredict; self.temperature = temperature; self.topK = topK; self.topP = topP
        self.minP = minP; self.repeatPenalty = repeatPenalty; self.seed = seed; self.stops = stops
    }

    public var json: JSONValue {
        var o: [String: JSONValue] = [
            "nPredict": JSONValue(nPredict), "temperature": JSONValue(temperature), "topK": JSONValue(topK),
            "topP": JSONValue(topP), "minP": JSONValue(minP), "repeatPenalty": JSONValue(repeatPenalty),
            "stops": JSONValue(strings: stops),
        ]
        if seed >= 0 { o["seed"] = JSONValue(seed) }
        return .object(o)
    }
    public func toJSON() -> String { json.jsonString }
}

/// One chat turn. The role is an open string (`system`, `user`, `assistant`) like the Kotlin side.
public struct ChatMessage: Sendable, Equatable, Hashable {
    public struct Role: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let system: Role = "system"
        public static let user: Role = "user"
        public static let assistant: Role = "assistant"
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) { self.role = role; self.content = content }
    public init(role: String, content: String) { self.role = Role(rawValue: role); self.content = content }
}

/// A chat rendered through a model's template (llama.cpp's `formatChat`).
public struct FormattedPrompt: Sendable, Equatable {
    public var prompt: String
    public var supportsThinking: Bool
    public var thinkingStart: String
    public var thinkingEnd: [String]
    public var stops: [String]

    public init(prompt: String, supportsThinking: Bool = false, thinkingStart: String = "", thinkingEnd: [String] = [], stops: [String] = []) {
        self.prompt = prompt; self.supportsThinking = supportsThinking; self.thinkingStart = thinkingStart
        self.thinkingEnd = thinkingEnd; self.stops = stops
    }
}

/// What one generation measured on the device.
public struct GenerationMetrics: Sendable, Equatable {
    public var promptTokens: Int
    public var promptTokensDecoded: Int
    public var generatedTokens: Int
    public var ttftMs: Double
    public var prefillMs: Double
    public var decodeMs: Double
    public var prefillTokPerSec: Double
    public var decodeTokPerSec: Double
    public var totalMs: Double
    /// "length", "eos", "stop", "cancelled", "stopped", "decode failed", or "" when the backend doesn't say.
    public var stopReason: String
    public var error: String?

    public init(
        promptTokens: Int = 0, promptTokensDecoded: Int = 0, generatedTokens: Int = 0, ttftMs: Double = -1,
        prefillMs: Double = 0, decodeMs: Double = 0, prefillTokPerSec: Double = 0, decodeTokPerSec: Double = 0,
        totalMs: Double = 0, stopReason: String = "", error: String? = nil
    ) {
        self.promptTokens = promptTokens; self.promptTokensDecoded = promptTokensDecoded
        self.generatedTokens = generatedTokens; self.ttftMs = ttftMs; self.prefillMs = prefillMs
        self.decodeMs = decodeMs; self.prefillTokPerSec = prefillTokPerSec; self.decodeTokPerSec = decodeTokPerSec
        self.totalMs = totalMs; self.stopReason = stopReason; self.error = error
    }

    /// Kotlin `GenerationMetrics.parse`: missing numbers read as 0 (ttft as -1).
    public init(json: String) throws {
        guard let v = JSONValue(jsonString: json), v.objectValue != nil else { throw CocoaError(.coderReadCorrupt) }
        self.init(
            promptTokens: v["promptTokens"]?.intValue ?? 0, promptTokensDecoded: v["promptTokensDecoded"]?.intValue ?? 0,
            generatedTokens: v["generatedTokens"]?.intValue ?? 0, ttftMs: v["ttftMs"]?.doubleValue ?? -1,
            prefillMs: v["prefillMs"]?.doubleValue ?? 0, decodeMs: v["decodeMs"]?.doubleValue ?? 0,
            prefillTokPerSec: v["prefillTokPerSec"]?.doubleValue ?? 0, decodeTokPerSec: v["decodeTokPerSec"]?.doubleValue ?? 0,
            totalMs: v["totalMs"]?.doubleValue ?? 0, stopReason: v["stopReason"]?.stringValue ?? "",
            error: v["error"]?.stringValue
        )
    }
}

/// What a generation stream yields: text pieces, then exactly one `.done`.
public enum GenerationEvent: Sendable, Equatable {
    case piece(String)
    case done(GenerationMetrics)
}

public struct BenchStats: Sendable, Equatable {
    public var mean: Double
    public var sd: Double
    public var runs: Int
    public init(mean: Double, sd: Double, runs: Int) { self.mean = mean; self.sd = sd; self.runs = runs }
}

public struct BenchResult: Sendable, Equatable {
    public var pp: BenchStats?
    public var tg: BenchStats?
    public var nPp: Int
    public var nTg: Int
    public var threads: Int
    public init(pp: BenchStats?, tg: BenchStats?, nPp: Int, nTg: Int, threads: Int) {
        self.pp = pp; self.tg = tg; self.nPp = nPp; self.nTg = nTg; self.threads = threads
    }
}
