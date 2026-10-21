import BoarCore
import Foundation
import Dispatch
import llama

/// What the worker learned while loading, for the session's `info` / `capabilities`.
struct LlamaLoaded: Sendable {
    var info: ModelInfo
    var capabilities: ModelCapabilities
    var embeddingDimensions: Int
}

/// Owns the llama.cpp model and context. Every native call runs on ONE dedicated serial queue (the actor's executor), so
/// calls are serialized (llama contexts are not thread-safe) and nothing ever blocks the main actor or the cooperative pool.
/// This is `boar_jni.cpp`: `Session`, `sync_prompt`, `generate`, `embed`, `bench`.
actor LlamaWorker {
    private let queue = DispatchSerialQueue(label: "team.sopa.boar.llama", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    nonisolated(unsafe) private var model: OpaquePointer?
    nonisolated(unsafe) private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var template: LlamaChatTemplate?
    /// Tokens currently in the KV cache (sequence 0).
    private var cached: [llama_token] = []
    private var nBatch = 512
    private var embeddingsEnabled = false
    /// Strongly held while its pointer is registered as the abort callback's data.
    private var control: RunControl?

    private let log = BoarLog.logger("llama")

    // MARK: Lifecycle

    func load(path: String, params: EngineParams, gpuLayers: Int, sessionCancel: StopFlag) throws -> LlamaLoaded {
        _ = LlamaBackend.ready
        guard FileManager.default.isReadableFile(atPath: path) else { throw LlamaError.fileNotFound(path) }

        guard let m = llama_model_load_from_file(path, LlamaParamMapping.modelParams(params, gpuLayers: gpuLayers)) else {
            throw LlamaError.loadFailed(path)
        }
        nBatch = max(1, params.nBatch)
        embeddingsEnabled = params.embeddings
        guard let c = llama_init_from_model(m, LlamaParamMapping.contextParams(params)) else {
            llama_model_free(m)
            throw LlamaError.contextFailed(path)
        }
        model = m
        ctx = c
        vocab = llama_model_get_vocab(m)

        // Embedding sessions never format chats (Kotlin: `if (!s->embeddings) templates = ...`).
        let hasTemplateInModel = llama_model_chat_template(m, nil) != nil
        if !embeddingsEnabled {
            let source = params.chatTemplate.isEmpty ? llama_model_chat_template(m, nil).map { String(cString: $0) } : params.chatTemplate
            template = LlamaChatTemplate.make(source: source)
        }

        var buf = [CChar](repeating: 0, count: 512)
        var arch: String?
        if llama_model_meta_val_str(m, "general.architecture", &buf, buf.count) > 0 { arch = String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let nEmbd = Int(llama_model_n_embd(m))
        let info = ModelInfo(
            name: name, backend: "llama.cpp", architecture: arch, sizeBytes: Int64(clamping: llama_model_size(m)),
            parameterCount: Int64(clamping: llama_model_n_params(m)), trainingContextTokens: Int(llama_model_n_ctx_train(m)),
            embeddingDimensions: nEmbd
        )
        let caps = ModelCapabilities(
            hasChatTemplate: template != nil, acceptsRawPrompt: true, supportsThinking: template?.supportsThinking ?? false,
            supportsPrewarm: !embeddingsEnabled, contextTokens: Int(llama_n_ctx(c))
        )
        if hasTemplateInModel && template == nil && !embeddingsEnabled {
            log.notice("chat template of \(name, privacy: .public) is not one llama_chat_apply_template knows; plain prompts only")
        }
        log.notice("loaded \(name, privacy: .public): ctx \(caps.contextTokens ?? 0), threads \(params.threads)/\(params.threadsBatch), \(self.template == nil ? "no" : "with") chat template")
        return LlamaLoaded(info: info, capabilities: caps, embeddingDimensions: nEmbd)
    }

    /// Frees the native objects. Idempotent; runs after any call already queued on the actor.
    func free() {
        if let ctx {
            llama_set_abort_callback(ctx, nil, nil)
            llama_free(ctx)
        }
        if let model { llama_model_free(model) }
        ctx = nil; model = nil; vocab = nil; template = nil; cached = []; control = nil
    }

    deinit {
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
    }

    // MARK: Abort callback

    /// Registers `control` so `llama_decode` returns (code 2) soon after a cancel instead of finishing a long prefill batch.
    private func attach(_ control: RunControl) {
        self.control = control
        guard let ctx else { return }
        let data = Unmanaged.passUnretained(control).toOpaque()
        llama_set_abort_callback(ctx, { data in
            guard let data else { return false }
            return Unmanaged<RunControl>.fromOpaque(data).takeUnretainedValue().shouldAbort
        }, data)
    }

    private func detach() {
        if let ctx { llama_set_abort_callback(ctx, nil, nil) }
        control = nil
    }

    // MARK: Tokens

    private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) -> [llama_token] {
        guard let vocab else { return [] }
        let length = text.utf8.count
        var capacity = length + 16
        for _ in 0..<2 {
            var out = [llama_token](repeating: 0, count: capacity)
            let n = Int(text.withCString { llama_tokenize(vocab, $0, Int32(length), &out, Int32(capacity), addSpecial, parseSpecial) })
            if n >= 0 { return Array(out[0..<n]) }
            if n == Int(Int32.min) { return [] }
            capacity = -n
        }
        return []
    }

    private func pieceBytes(_ token: llama_token) -> [UInt8] {
        guard let vocab else { return [] }
        return withUnsafeTemporaryAllocation(of: CChar.self, capacity: 128) { buf in
            let n = Int(llama_token_to_piece(vocab, token, buf.baseAddress, 128, 0, false))
            if n >= 0 { return buf[0..<n].map { UInt8(bitPattern: $0) } }
            var big = [CChar](repeating: 0, count: -n)
            let m = Int(llama_token_to_piece(vocab, token, &big, Int32(-n), 0, false))
            return big[0..<max(0, m)].map { UInt8(bitPattern: $0) }
        }
    }

    // MARK: Prompt cache

    /// Decode tokens[from...] in nBatch chunks; false on failure or cancel. Only the last token's logits are needed.
    private func decode(_ tokens: [llama_token], from: Int, control: RunControl) -> Bool {
        guard let ctx else { return false }
        var i = from
        while i < tokens.count {
            if control.shouldAbort { return false }
            let n = min(nBatch, tokens.count - i)
            let ok = tokens.withUnsafeBufferPointer { p -> Bool in
                let batch = llama_batch_get_one(UnsafeMutablePointer(mutating: p.baseAddress! + i), Int32(n))
                return llama_decode(ctx, batch) == 0
            }
            if !ok { return false }
            i += n
        }
        return true
    }

    /// Bring the KV cache to `tokens`, reusing the common prefix. Returns how many tokens were decoded, or -1.
    private func syncPrompt(_ tokens: [llama_token], control: RunControl) -> Int {
        guard let ctx else { return -1 }
        var keep = 0
        while keep < cached.count && keep < tokens.count && cached[keep] == tokens[keep] { keep += 1 }
        // The last prompt token must be decoded again so its logits exist.
        if keep == tokens.count && keep > 0 { keep -= 1 }
        let mem = llama_get_memory(ctx)
        if !llama_memory_seq_rm(mem, 0, llama_pos(keep), -1) {
            llama_memory_clear(mem, true)
            keep = 0
        }
        cached = Array(tokens[0..<keep])
        if !decode(tokens, from: keep, control: control) {
            llama_memory_clear(mem, true)
            cached = []
            return -1
        }
        cached = tokens
        return tokens.count - keep
    }

    // MARK: Chat formatting

    func formatChat(_ messages: [ChatMessage], enableThinking: Bool) throws -> FormattedPrompt {
        guard ctx != nil else { throw ModelSeamError.notLoaded }
        guard let template else { throw ModelSeamError.chatTemplate("model has no usable chat template") }
        return try template.format(messages, enableThinking: enableThinking)
    }

    // MARK: Generation

    /// Streams one generation into `continuation` (pieces, then `.done`, then finish) or finishes it with a thrown error.
    func generate(
        _ request: GenerationRequest, sessionCancel: StopFlag, run: RunControl,
        continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
    ) {
        if run.stop.isSet { continuation.finish(); return }
        guard ctx != nil else { continuation.finish(throwing: ModelSeamError.notLoaded); return }
        if embeddingsEnabled {
            continuation.finish(throwing: ModelSeamError.unsupportedInput("session was opened for embeddings")); return
        }
        do {
            let (prompt, templateStops) = try renderPrompt(request)
            sessionCancel.clear()  // a cancel() that arrived before the generation started is lost
            attach(run)
            defer { detach() }
            let stops = mergedStops(templateStops, request.sampling.stops)
            let metrics = try runGeneration(prompt: prompt, sampling: request.sampling, stops: stops, control: run) { piece in
                if case .terminated = continuation.yield(.piece(piece)) { run.stop.set(); return false }
                return true
            }
            continuation.yield(.done(metrics))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Reads `input` into the KV cache without generating (nPredict 0).
    func prewarm(_ input: GenerationRequest.Input, enableThinking: Bool, sessionCancel: StopFlag, run: RunControl) {
        guard ctx != nil, !embeddingsEnabled else { return }
        do {
            let (prompt, _) = try renderPrompt(GenerationRequest(input: input, sampling: Sampling(nPredict: 0), enableThinking: enableThinking))
            sessionCancel.clear()
            attach(run)
            defer { detach() }
            _ = try runGeneration(prompt: prompt, sampling: Sampling(nPredict: 0), stops: [], control: run) { _ in true }
        } catch {
            log.debug("prewarm skipped: \(String(describing: error), privacy: .public)")
        }
    }

    private func renderPrompt(_ request: GenerationRequest) throws -> (prompt: String, stops: [String]) {
        switch request.input {
        case .prompt(let p): return (p, [])
        case .messages(let msgs):
            guard let template else { throw ModelSeamError.chatTemplate("model has no usable chat template") }
            let f = try template.format(msgs, enableThinking: request.enableThinking)
            return (f.prompt, f.stops)
        }
    }

    /// The Kotlin `Java_..._generate` body. Throws for a prompt that can't run; cancel and stop come back as metrics.
    private func runGeneration(
        prompt: String, sampling: Sampling, stops: [String], control: RunControl, emit: (String) -> Bool
    ) throws -> GenerationMetrics {
        guard let ctx, let vocab else { throw ModelSeamError.notLoaded }
        let t0 = LlamaClock.nowMs()
        let tokens = tokenize(prompt, addSpecial: llama_vocab_get_add_bos(vocab), parseSpecial: true)
        var m = GenerationMetrics()
        m.promptTokens = tokens.count
        if tokens.count >= Int(llama_n_ctx(ctx)) { throw ModelSeamError.generationFailed("prompt longer than the context") }

        let decoded = syncPrompt(tokens, control: control)
        llama_synchronize(ctx)  // Metal decodes are asynchronous: wait, so prefill time and tok/s are honest
        let tPrefill = LlamaClock.nowMs()
        m.promptTokensDecoded = decoded
        m.prefillMs = tPrefill - t0
        log.info("generate: \(tokens.count) prompt tokens, \(decoded) decoded, prefill \(Int(tPrefill - t0)) ms, nPredict \(sampling.nPredict)")
        if decoded < 0 {
            if control.shouldAbort {
                m.promptTokensDecoded = 0
                m.stopReason = "cancelled"
                m.ttftMs = -1
                m.totalMs = LlamaClock.nowMs() - t0
                return m
            }
            throw ModelSeamError.generationFailed("prefill failed")
        }

        let smpl = makeSampler(sampling)
        defer { llama_sampler_free(smpl) }

        var filter = StopSequenceFilter(stops: stops)
        var pending: [UInt8] = []
        var nGen = 0
        var tFirst = 0.0
        var stopReason = "length"
        while nGen < sampling.nPredict {
            if control.shouldAbort { stopReason = "cancelled"; break }
            var tok = llama_sampler_sample(smpl, ctx, -1)
            if tFirst == 0 { tFirst = LlamaClock.nowMs() }
            if llama_vocab_is_eog(vocab, tok) { stopReason = "eos"; break }
            pending.append(contentsOf: pieceBytes(tok))
            let ready = completeUTF8Length(pending)
            if ready > 0 {
                let text = String(decoding: pending[0..<ready], as: UTF8.self)
                pending.removeFirst(ready)
                let out = filter.push(text)
                if !out.isEmpty && !emit(out) { stopReason = "stopped"; nGen += 1; break }
                if filter.hitStop { stopReason = "stop"; nGen += 1; break }
            }
            let ok = withUnsafeMutablePointer(to: &tok) { llama_decode(ctx, llama_batch_get_one($0, 1)) == 0 }
            if !ok {
                if control.shouldAbort {
                    // An aborted decode may have written the token: drop the cache rather than trust it.
                    llama_memory_clear(llama_get_memory(ctx), true)
                    cached = []
                    stopReason = "cancelled"
                } else {
                    stopReason = "decode failed"
                }
                break
            }
            cached.append(tok)
            nGen += 1
        }
        // What the filter held back is not a stop (the end of the text): show it.
        if stopReason != "stop" && stopReason != "stopped" {
            let tail = filter.finish()
            if !tail.isEmpty { _ = emit(tail) }
        }
        let tEnd = LlamaClock.nowMs()
        m.generatedTokens = nGen
        m.stopReason = stopReason
        m.ttftMs = tFirst > 0 ? tFirst - t0 : -1
        let decodeMs = tFirst > 0 ? tEnd - tFirst : 0
        m.decodeMs = decodeMs
        m.prefillTokPerSec = decoded > 0 && (tPrefill - t0) > 0 ? Double(decoded) * 1000 / (tPrefill - t0) : 0
        m.decodeTokPerSec = nGen > 1 && decodeMs > 0 ? Double(nGen - 1) * 1000 / decodeMs : 0
        m.totalMs = tEnd - t0
        return m
    }

    /// penalties, top-k, top-p, min-p, temperature, dist (or greedy when temperature <= 0), in the Kotlin order.
    private func makeSampler(_ s: Sampling) -> UnsafeMutablePointer<llama_sampler> {
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if s.temperature <= 0 {
            llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
        } else {
            let nVocab = vocab.map { llama_vocab_n_tokens($0) } ?? 0
            llama_sampler_chain_add(smpl, llama_sampler_init_penalties(nVocab, 64, s.repeatPenalty, 0, 0))
            llama_sampler_chain_add(smpl, llama_sampler_init_top_k(Int32(s.topK)))
            llama_sampler_chain_add(smpl, llama_sampler_init_top_p(s.topP, 1))
            llama_sampler_chain_add(smpl, llama_sampler_init_min_p(s.minP, 1))
            llama_sampler_chain_add(smpl, llama_sampler_init_temp(s.temperature))
            llama_sampler_chain_add(smpl, llama_sampler_init_dist(LlamaParamMapping.samplerSeed(s.seed)))
        }
        return smpl
    }

    // MARK: Embeddings

    /// One embedding per call, pooled by the model's own pooling type; L2-normalized when asked.
    func embed(_ text: String, normalize: Bool, sessionCancel: StopFlag, run: RunControl) throws -> [Float] {
        guard let ctx, let model else { throw ModelSeamError.notLoaded }
        guard embeddingsEnabled else { throw ModelSeamError.unsupportedInput("session was not opened with embeddings") }
        sessionCancel.clear()
        var tokens = tokenize(text, addSpecial: true, parseSpecial: true)
        let nCtx = Int(llama_n_ctx(ctx))
        if tokens.count > nCtx { tokens = Array(tokens[0..<nCtx]) }
        if tokens.isEmpty { return [] }
        let mem = llama_get_memory(ctx)
        llama_memory_clear(mem, true)
        cached = []
        attach(run)
        defer { detach() }

        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        batch.n_tokens = Int32(tokens.count)
        for (i, t) in tokens.enumerated() {
            batch.token[i] = t
            batch.pos[i] = llama_pos(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 1
        }
        let rc = llama_decode(ctx, batch)
        if rc != 0 { throw ModelSeamError.generationFailed("embedding decode failed (\(rc))") }
        let nEmbd = Int(llama_model_n_embd(model))
        guard let e = llama_get_embeddings_seq(ctx, 0) ?? llama_get_embeddings_ith(ctx, -1) else {
            throw ModelSeamError.generationFailed("no embedding output")
        }
        var v = Array(UnsafeBufferPointer(start: e, count: nEmbd))
        if normalize {
            var sum = 0.0
            for x in v { sum += Double(x) * Double(x) }
            let inv: Float = sum > 0 ? Float(1.0 / sum.squareRoot()) : 0
            for i in v.indices { v[i] *= inv }
        }
        return v
    }

    // MARK: Bench

    /// llama-bench style: pp = prompt processing of nPp synthetic tokens, tg = nTg tokens one at a time.
    func bench(nPp: Int, nTg: Int, reps: Int, sessionCancel: StopFlag, run: RunControl) throws -> BenchResult {
        guard let ctx, let vocab else { throw ModelSeamError.notLoaded }
        sessionCancel.clear()
        attach(run)
        defer { detach() }
        let nVocab = Int(llama_vocab_n_tokens(vocab))
        var pp: [Double] = [], tg: [Double] = []
        let mem = llama_get_memory(ctx)
        var r = 0
        while r < reps && !run.shouldAbort {
            llama_memory_clear(mem, true)
            cached = []
            // Kotlin: (i * 2654435761u + r) % n_vocab in 32-bit unsigned arithmetic.
            let toks: [llama_token] = (0..<max(0, nPp)).map {
                llama_token((UInt32(truncatingIfNeeded: $0) &* 2_654_435_761 &+ UInt32(r)) % UInt32(nVocab))
            }
            let t0 = LlamaClock.nowMs()
            if nPp > 0 && !decode(toks, from: 0, control: run) { break }
            llama_synchronize(ctx)
            let t1 = LlamaClock.nowMs()
            if nPp > 0 { pp.append(Double(nPp) * 1000 / (t1 - t0)) }
            var tok = toks.last ?? 1
            let t2 = LlamaClock.nowMs()
            var done = 0
            while done < nTg && !run.shouldAbort {
                let ok = withUnsafeMutablePointer(to: &tok) { llama_decode(ctx, llama_batch_get_one($0, 1)) == 0 }
                if !ok { break }
                tok = llama_token((UInt32(truncatingIfNeeded: tok) &* 31 &+ 7) % UInt32(nVocab))
                done += 1
            }
            llama_synchronize(ctx)
            let t3 = LlamaClock.nowMs()
            if done > 0 { tg.append(Double(done) * 1000 / (t3 - t2)) }
            r += 1
        }
        llama_memory_clear(mem, true)
        cached = []
        func stats(_ v: [Double]) -> BenchStats? {
            if v.isEmpty { return nil }
            let mean = v.reduce(0, +) / Double(v.count)
            let variance = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            return BenchStats(mean: mean, sd: v.count > 1 ? (variance / Double(v.count - 1)).squareRoot() : 0, runs: v.count)
        }
        return BenchResult(pp: stats(pp), tg: stats(tg), nPp: nPp, nTg: nTg, threads: Int(llama_n_threads(ctx)))
    }
}
