import Foundation

/// Advanced engine tweaks: every knob the engine has, each Auto (nil) unless the user sets it. A set value is clamped to
/// what the device can run, so a tweak can make the app slower but never stop it from starting. Applied on the next model load.
public struct EngineTweaks: Sendable, Equatable, Codable {
    /// "auto", "best" (ggml's own pick) or a variant name; see `CpuVariants`.
    public var cpuBuild: String
    /// Threads for generation. Auto: the fast cores, at most 4.
    public var threads: Int?
    /// Threads for reading the prompt. Auto: same as `threads`.
    public var threadsBatch: Int?
    /// "auto" (the fast cores), "all" (the OS places threads) or a core list like "4,5,6,7".
    public var cores: String
    /// Keep threads strictly on `cores` (llama.cpp's strict cpumask).
    public var strictCpu: Bool
    /// Context window in tokens. Auto: `contextSizeForRam` (2048 up to 4.5 GB of RAM, 3072 up to 6.5 GB, else 4096).
    public var contextTokens: Int?
    /// Prompt batch and micro-batch. Auto: 512 and 512.
    public var batch: Int?
    public var microBatch: Int?
    /// KV cache type for keys and values. Auto: F16.
    public var kvCache: KvType?
    public var flashAttention: FlashAttn
    /// How weights are read: memory-mapped (Auto), mapped and locked in RAM, or read into memory.
    public var loadMode: LoadMode?
    /// MoE expert streaming. Auto: off.
    public var lazyExperts: LazyMode?
    /// Time limit for one generation, in seconds; 0 = no limit. Auto: `autoStageTimeoutMs`, which grows with the token cap.
    /// A generation that hits the limit keeps what it wrote.
    public var stageTimeoutSeconds: Int?
    /// Repacked weights. Auto: on (prompts read about 2x faster), except the load after a repacked load got the app killed.
    public var weightRepack: Bool?
    /// Let a thinking model reason before it answers. Auto: off, so the answer's token cap isn't spent on reasoning.
    public var thinking: Bool?

    public static let autoCores = "auto"
    public static let allCores = "all"

    public init(
        cpuBuild: String = CpuVariants.autoSetting, threads: Int? = nil, threadsBatch: Int? = nil, cores: String = EngineTweaks.autoCores,
        strictCpu: Bool = false, contextTokens: Int? = nil, batch: Int? = nil, microBatch: Int? = nil, kvCache: KvType? = nil,
        flashAttention: FlashAttn = .auto, loadMode: LoadMode? = nil, lazyExperts: LazyMode? = nil,
        stageTimeoutSeconds: Int? = nil, weightRepack: Bool? = nil, thinking: Bool? = nil
    ) {
        self.cpuBuild = cpuBuild; self.threads = threads; self.threadsBatch = threadsBatch; self.cores = cores
        self.strictCpu = strictCpu; self.contextTokens = contextTokens; self.batch = batch; self.microBatch = microBatch
        self.kvCache = kvCache; self.flashAttention = flashAttention; self.loadMode = loadMode; self.lazyExperts = lazyExperts
        self.stageTimeoutSeconds = stageTimeoutSeconds; self.weightRepack = weightRepack; self.thinking = thinking
    }

    public var thinkingEnabled: Bool { thinking ?? false }

    /// The time limit for a Deep Research write-up. Auto: none (Stop ends it at any point). A limit set by hand applies as for any stage.
    public func writeUpTimeoutMs(nPredict: Int) -> Int64? {
        stageTimeoutSeconds == nil ? nil : stageTimeoutMs(nPredict: nPredict)
    }

    /// The limit for a generation of up to `nPredict` tokens, or nil for none.
    public func stageTimeoutMs(nPredict: Int) -> Int64? {
        guard let s = stageTimeoutSeconds else { return Self.autoStageTimeoutMs(nPredict: nPredict) }
        return s <= 0 ? nil : Int64(s) * 1000
    }

    public struct Resolved: Sendable, Equatable {
        public var params: EngineParams
        public var cpuSetting: String
        public var notes: [String]
    }

    /// The engine parameters these tweaks give on this device, with a note for each value that was clamped.
    /// `totalRamBytes` sizes the Auto context; 0 (unknown) gives 4096.
    public func resolve(_ topology: CpuTopology, totalRamBytes: Int64 = 0) -> Resolved {
        var notes: [String] = []
        let n = max(topology.cores.count, 1)
        let autoBig = topology.autoCores
        let big = autoBig.isEmpty ? topology.cores.map(\.id) : autoBig
        func clamp(_ name: String, _ v: Int, _ lo: Int, _ hi: Int) -> Int {
            let c = min(max(v, lo), hi)
            if c != v { notes.append("\(name) \(v) → \(c) (allowed \(lo)–\(hi))") }
            return c
        }

        let coreIds: [Int]?
        switch cores {
        case Self.autoCores: coreIds = big
        case Self.allCores: coreIds = nil
        default:
            var seen = Set<Int>()
            let ids = cores.split(whereSeparator: { $0 == "," || $0 == " " })
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { id in topology.cores.contains { $0.id == id } }
                .filter { seen.insert($0).inserted }
            if ids.isEmpty {
                notes.append("cores \"\(cores)\" → the fast cores (no valid core in the list)")
                coreIds = big
            } else {
                coreIds = ids
            }
        }
        let maxThreads = coreIds?.count ?? n
        let t = threads.map { clamp("threads", $0, 1, n) } ?? max(min(big.count, 4), 1)
        if threads == nil && t > maxThreads { notes.append("threads \(t) > cores \(maxThreads)") }
        let tb = threadsBatch.map { clamp("prompt threads", $0, 1, n) } ?? t
        let ctx = contextTokens.map { clamp("context", $0, 256, 131072) } ?? Self.contextSizeForRam(totalRamBytes)
        let b = batch.map { clamp("batch", $0, 32, 4096) } ?? 512
        let ub = microBatch.map { clamp("micro-batch", $0, 32, b) } ?? min(512, b)
        let params = EngineParams(
            nCtx: ctx, nBatch: b, nUbatch: ub, threads: t, threadsBatch: tb,
            cpus: coreIds.map { topology.cpuList($0) } ?? "", strictCpu: strictCpu && coreIds != nil,
            typeK: kvCache ?? .f16, typeV: kvCache ?? .f16, flashAttn: flashAttention,
            loadMode: loadMode ?? .mmap, lazyMode: lazyExperts ?? .off, repack: weightRepack ?? true
        )
        return Resolved(params: params, cpuSetting: cpuBuild, notes: notes)
    }

    /// True when nothing is overridden.
    public var isAuto: Bool { self == EngineTweaks() }

    /// memoryFit.ts contextSizeForRam: a smaller KV cache on small devices, so the model load is less likely to be killed.
    public static func contextSizeForRam(_ totalRamBytes: Int64) -> Int {
        let gib = 1024.0 * 1024 * 1024
        let ram = Double(totalRamBytes)
        if totalRamBytes <= 0 { return 4096 }
        if ram <= 4.5 * gib { return 2048 }
        if ram <= 6.5 * gib { return 3072 }
        return 4096
    }

    /// Auto time limit: 2 minutes plus half a second per token allowed, i.e. room for a device generating at 2 tok/s.
    public static func autoStageTimeoutMs(nPredict: Int) -> Int64 { 120_000 + Int64(max(nPredict, 0)) * 500 }

    // MARK: JSON (Kotlin: encodeDefaults = false, ignoreUnknownKeys = true)

    private enum CodingKeys: String, CodingKey {
        case cpuBuild, threads, threadsBatch, cores, strictCpu, contextTokens, batch, microBatch, kvCache, flashAttention
        case loadMode, lazyExperts, stageTimeoutSeconds, weightRepack, thinking
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cpuBuild: try c.decodeIfPresent(String.self, forKey: .cpuBuild) ?? CpuVariants.autoSetting,
            threads: try c.decodeIfPresent(Int.self, forKey: .threads),
            threadsBatch: try c.decodeIfPresent(Int.self, forKey: .threadsBatch),
            cores: try c.decodeIfPresent(String.self, forKey: .cores) ?? Self.autoCores,
            strictCpu: try c.decodeIfPresent(Bool.self, forKey: .strictCpu) ?? false,
            contextTokens: try c.decodeIfPresent(Int.self, forKey: .contextTokens),
            batch: try c.decodeIfPresent(Int.self, forKey: .batch),
            microBatch: try c.decodeIfPresent(Int.self, forKey: .microBatch),
            kvCache: try c.decodeIfPresent(KvType.self, forKey: .kvCache),
            flashAttention: try c.decodeIfPresent(FlashAttn.self, forKey: .flashAttention) ?? .auto,
            loadMode: try c.decodeIfPresent(LoadMode.self, forKey: .loadMode),
            lazyExperts: try c.decodeIfPresent(LazyMode.self, forKey: .lazyExperts),
            stageTimeoutSeconds: try c.decodeIfPresent(Int.self, forKey: .stageTimeoutSeconds),
            weightRepack: try c.decodeIfPresent(Bool.self, forKey: .weightRepack),
            thinking: try c.decodeIfPresent(Bool.self, forKey: .thinking)
        )
    }

    /// Only the knobs that differ from Auto are written: all Auto encodes to `{}`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if cpuBuild != CpuVariants.autoSetting { try c.encode(cpuBuild, forKey: .cpuBuild) }
        try c.encodeIfPresent(threads, forKey: .threads)
        try c.encodeIfPresent(threadsBatch, forKey: .threadsBatch)
        if cores != Self.autoCores { try c.encode(cores, forKey: .cores) }
        if strictCpu { try c.encode(strictCpu, forKey: .strictCpu) }
        try c.encodeIfPresent(contextTokens, forKey: .contextTokens)
        try c.encodeIfPresent(batch, forKey: .batch)
        try c.encodeIfPresent(microBatch, forKey: .microBatch)
        try c.encodeIfPresent(kvCache, forKey: .kvCache)
        if flashAttention != .auto { try c.encode(flashAttention, forKey: .flashAttention) }
        try c.encodeIfPresent(loadMode, forKey: .loadMode)
        try c.encodeIfPresent(lazyExperts, forKey: .lazyExperts)
        try c.encodeIfPresent(stageTimeoutSeconds, forKey: .stageTimeoutSeconds)
        try c.encodeIfPresent(weightRepack, forKey: .weightRepack)
        try c.encodeIfPresent(thinking, forKey: .thinking)
    }

    public func toJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Saved tweaks; unreadable or missing → all Auto.
    public static func fromJSON(_ s: String?) -> EngineTweaks {
        guard let s, let data = s.data(using: .utf8), let t = try? JSONDecoder().decode(EngineTweaks.self, from: data) else { return EngineTweaks() }
        return t
    }
}
