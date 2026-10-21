import BoarCore
import Foundation
import Synchronization
import os
import llama

/// Failures of loading or driving a llama.cpp model that are not part of the model seam (`ModelSeamError` covers generation).
public enum LlamaError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The GGUF path doesn't exist or isn't readable.
    case fileNotFound(String)
    /// llama.cpp refused the file (not a GGUF, unsupported architecture, out of memory); see the `llama` log category.
    case loadFailed(String)
    /// The context couldn't be created (usually memory: try a smaller `nCtx`).
    case contextFailed(String)

    public var description: String {
        switch self {
        case .fileNotFound(let p): "model file not found: \(p)"
        case .loadFailed(let p): "could not load model: \(p)"
        case .contextFailed(let p): "could not create the context for: \(p)"
        }
    }
}

/// A flag any thread can raise and the llama worker polls (between tokens, and inside `llama_decode` through the abort callback).
final class StopFlag: Sendable {
    private let value = Atomic<Bool>(false)
    func set() { value.store(true, ordering: .relaxed) }
    func clear() { value.store(false, ordering: .relaxed) }
    var isSet: Bool { value.load(ordering: .relaxed) }
}

/// What a running llama call watches: the session-wide cancel (`LlamaSession.cancel()`) and its own stop (the consumer went away).
final class RunControl: Sendable {
    let sessionCancel: StopFlag
    let stop = StopFlag()
    init(sessionCancel: StopFlag) { self.sessionCancel = sessionCancel }
    var shouldAbort: Bool { sessionCancel.isSet || stop.isSet }
}

enum LlamaBackend {
    private static let logger = BoarLog.logger("llama")

    /// Initialises ggml/llama once per process and routes the native log to os.Logger. Safe to call from any thread.
    static let ready: Void = {
        llama_log_set({ level, text, _ in
            guard let text else { return }
            let line = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return }
            if level == GGML_LOG_LEVEL_ERROR {
                LlamaBackend.logger.error("\(line, privacy: .public)")
            } else if level == GGML_LOG_LEVEL_WARN {
                LlamaBackend.logger.warning("\(line, privacy: .public)")
            } else {
                LlamaBackend.logger.debug("\(line, privacy: .public)")
            }
        }, nil)
        // No Metal device at all (not only zero offloaded layers): ggml would still build its shader library on init.
        if !LlamaSession.metalEnabled { setenv("GGML_METAL_DEVICES", "0", 0) }
        llama_backend_init()
    }()
}

enum LlamaClock {
    static func nowMs() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
    }
}

/// Length of the longest prefix of `bytes` that ends on a complete UTF-8 character (the Kotlin `complete_utf8`).
func completeUTF8Length(_ bytes: [UInt8]) -> Int {
    let n = bytes.count
    var back = 1
    while back <= 4 && back <= n {
        let c = bytes[n - back]
        if c & 0xC0 == 0x80 { back += 1; continue }  // continuation byte
        let need = c & 0x80 == 0 ? 1 : c & 0xE0 == 0xC0 ? 2 : c & 0xF0 == 0xE0 ? 3 : c & 0xF8 == 0xF0 ? 4 : 1
        return back >= need ? n : n - back
    }
    return n
}

/// `stops` from the template first, then the request's, without repeats or empty strings.
func mergedStops(_ lists: [String]...) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for s in lists.joined() where !s.isEmpty && seen.insert(s).inserted { out.append(s) }
    return out
}

/// The seam's `Sampling` / `EngineParams` as llama.cpp structs (pure, so tests can check the mapping without a model).
enum LlamaParamMapping {
    static func modelParams(_ p: EngineParams, gpuLayers: Int) -> llama_model_params {
        var mp = llama_model_default_params()
        mp.n_gpu_layers = Int32(gpuLayers)
        mp.load_mode = llama_load_mode(rawValue: Int32(p.loadMode.code))
        mp.lazy_mode = llama_lazy_mode(rawValue: UInt32(p.lazyMode.code))
        // Repacked weights (llama.cpp's fast ARM layouts) live in app memory; false keeps the mapped file (llama-cli --no-repack).
        mp.use_extra_bufts = p.repack
        return mp
    }

    static func contextParams(_ p: EngineParams) -> llama_context_params {
        var cp = llama_context_default_params()
        cp.n_ctx = UInt32(max(1, p.nCtx))
        cp.n_batch = UInt32(max(1, p.nBatch))
        cp.n_ubatch = UInt32(max(1, p.nUbatch))
        cp.n_threads = Int32(max(1, p.threads))
        cp.n_threads_batch = Int32(max(1, p.threadsBatch))
        cp.type_k = ggml_type(rawValue: UInt32(p.typeK.ggml))
        cp.type_v = ggml_type(rawValue: UInt32(p.typeV.ggml))
        cp.flash_attn_type = llama_flash_attn_type(rawValue: Int32(p.flashAttn.code))
        cp.embeddings = p.embeddings
        cp.no_perf = false
        return cp
    }

    /// Kotlin: `sp.value("seed", LLAMA_DEFAULT_SEED)`; the seed key is only sent when >= 0.
    static func samplerSeed(_ seed: Int) -> UInt32 {
        seed >= 0 ? UInt32(truncatingIfNeeded: seed) : UInt32.max
    }
}
