import Testing
@testable import BoarCore

@Suite struct EngineTweaksTests {
    /// Dimensity 8300 (X6 Pro): 1 prime + 3 big + 4 little.
    let x6 = CpuTopology(cores:
        (0..<4).map { CpuTopology.Core(id: $0, maxKhz: 2_200_000) } + [CpuTopology.Core(id: 4, maxKhz: 3_350_000)]
        + (0..<3).map { CpuTopology.Core(id: 5 + $0, maxKhz: 3_200_000) })
    let x6Features = CpuVariants.readFeatures(cpuinfo:
        "processor\t: 0\nFeatures\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 sve asimdfhm dit uscat ilrcpc flagm sb paca pacg dcpodp sve2 sveaes svepmull svebitperm svesha3 svesm4 flagm2 frint svei8mm svebf16 i8mm bf16 bti mte mte3\n")
    /// Snapdragon 870 (POCO F3): dotprod and fp16, no i8mm.
    let f3Features: Set<String> = ["fp", "asimd", "asimdhp", "asimddp", "fphp"]

    @Test func allAutoGivesTheMeasuredDefaults() {
        let r = EngineTweaks().resolve(x6)
        #expect(r.params.threads == 4)
        #expect(r.params.cpus == "4,5,6,7")
        #expect(r.params.nCtx == 4096)
        #expect(r.params.typeK == .f16)
        #expect(r.notes.isEmpty)
        #expect(EngineTweaks().isAuto)
    }

    /// Cores from (count, max kHz) groups, numbered from 0 in the order given (sysfs lists the little cores first).
    func soc(_ groups: (Int, Int64)...) -> CpuTopology {
        var id = 0
        var cores: [CpuTopology.Core] = []
        for (n, khz) in groups { for _ in 0..<n { cores.append(.init(id: id, maxKhz: khz)); id += 1 } }
        return CpuTopology(cores: cores)
    }

    @Test func autoThreadsAre4OnTheFastCoresOfEveryLayoutNeverTheLittleOnes() {
        let g1 = soc((4, 1_803_000), (2, 2_253_000), (2, 2_802_000))   // Tensor G1
        let g2 = soc((4, 1_803_000), (2, 2_348_000), (2, 2_850_000))   // Tensor G2
        let sd870 = soc((4, 1_804_800), (3, 2_419_200), (1, 3_187_200))
        let g3 = soc((4, 1_704_000), (4, 2_450_000), (1, 2_910_000))   // Tensor G3
        let sixTwo = soc((6, 2_000_000), (2, 2_200_000))               // Helio G99 class
        let flat = soc((8, 0))                                         // one cluster, or no frequency readable

        #expect(g1.bigCores == [6, 7])
        #expect(g1.autoCores == [4, 5, 6, 7])
        #expect(g2.autoCores == [4, 5, 6, 7])
        #expect(sd870.autoCores == [4, 5, 6, 7])
        #expect(x6.autoCores == [4, 5, 6, 7])
        #expect(g3.autoCores == [4, 5, 6, 7, 8])
        #expect(sixTwo.autoCores == [6, 7])
        #expect(flat.autoCores == Array(0...7))

        for t in [g1, g2, sd870, x6, g3, flat] { #expect(EngineTweaks().resolve(t).params.threads == 4) }
        #expect(EngineTweaks().resolve(g1).params.cpus == "4,5,6,7")
        #expect(EngineTweaks().resolve(sixTwo).params.threads == 2)
        // The user's own setting still wins.
        #expect(EngineTweaks(threads: 2, cores: "6,7").resolve(g1).params.threads == 2)
        #expect(EngineTweaks(threads: 2, cores: "6,7").resolve(g1).params.cpus == "6,7")
    }

    @Test func everyKnobCanBeSetAndImpossibleValuesAreClampedWithANote() {
        let r = EngineTweaks(threads: 64, cores: "all", contextTokens: 100, batch: 256, microBatch: 1024, kvCache: .q8_0, flashAttention: .on).resolve(x6)
        #expect(r.params.threads == 8)
        #expect(r.params.cpus == "")
        #expect(r.params.nCtx == 256)
        #expect(r.params.nUbatch == 256)
        #expect(r.params.typeV == .q8_0)
        #expect(r.notes.count == 3)
        #expect(EngineTweaks(cores: "3, 1, 99").resolve(x6).params.cpus == "1,3")
        #expect(EngineTweaks(cores: "none").resolve(x6).params.cpus == "4,5,6,7")
    }

    @Test func savedTweaksRoundTripAndABrokenFileMeansAllAuto() {
        let t = EngineTweaks(cpuBuild: "android_armv9.0_1", threads: 6, kvCache: .q4_0)
        #expect(EngineTweaks.fromJSON(t.toJSON()) == t)
        #expect(EngineTweaks().toJSON() == "{}")
        #expect(EngineTweaks.fromJSON("{not json") == EngineTweaks())
        #expect(EngineTweaks.fromJSON(nil) == EngineTweaks())
        // Kotlin enum names are the stored form; unknown keys are ignored.
        #expect(EngineTweaks.fromJSON(#"{"kvCache":"Q8_0","loadMode":"MMAP_MLOCK","futureKnob":1}"#) == EngineTweaks(kvCache: .q8_0, loadMode: .mmapMlock))
    }

    @Test func cpuBuildAutoPicksArmv86OnTheX6AndLeavesTheF3ToGgml() {
        #expect(CpuVariants.auto(x6Features) == "android_armv8.6_1")
        #expect(CpuVariants.supported(x6Features).map(\.name) == ["android_armv8.0_1", "android_armv8.2_1", "android_armv8.2_2", "android_armv8.6_1", "android_armv9.0_1"])
        #expect(CpuVariants.auto(f3Features) == nil)
        #expect(CpuVariants.supported(f3Features).map(\.name) == ["android_armv8.0_1", "android_armv8.2_1", "android_armv8.2_2"])
        #expect(CpuVariants.auto(x6Features.union(["sme"])) == nil)
    }

    @Test func cpuBuildASettingTheDeviceCantRunFallsBackToAuto() {
        #expect(CpuVariants.resolve("android_armv9.0_1", x6Features) == "android_armv9.0_1")
        #expect(CpuVariants.resolve("best", x6Features) == nil)
        #expect(CpuVariants.resolve("android_armv8.6_1", f3Features) == nil)
        #expect(CpuVariants.resolve("android_armv9.2_2", x6Features) == "android_armv8.6_1")
        #expect(CpuVariants.resolve(nil, x6Features) == "android_armv8.6_1")
    }

    @Test func generationTimeLimitAutoGrowsWithTheTokenCapTheUserCanFixItOrTurnItOff() {
        #expect(EngineTweaks().stageTimeoutMs(nPredict: 512) == Int64(376_000))
        #expect(EngineTweaks().stageTimeoutMs(nPredict: 2048) == Int64(120_000 + 2048 * 500))
        #expect(EngineTweaks(stageTimeoutSeconds: 300).stageTimeoutMs(nPredict: 2048) == 300_000)
        #expect(EngineTweaks(stageTimeoutSeconds: 0).stageTimeoutMs(nPredict: 2048) == nil)
        #expect(EngineTweaks.fromJSON(EngineTweaks(stageTimeoutSeconds: 0).toJSON()) == EngineTweaks(stageTimeoutSeconds: 0))
    }

    @Test func aDeepResearchWriteUpHasNoTimeLimitOnAutoAndALimitSetByHandStillApplies() {
        #expect(EngineTweaks().writeUpTimeoutMs(nPredict: 2048) == nil)
        #expect(EngineTweaks(stageTimeoutSeconds: 300).writeUpTimeoutMs(nPredict: 2048) == 300_000)
        #expect(EngineTweaks(stageTimeoutSeconds: 0).writeUpTimeoutMs(nPredict: 2048) == nil)
    }

    @Test func autoContextFollowsTheDevicesRamAsContextSizeForRam() {
        let gib: Int64 = 1024 * 1024 * 1024
        let topo = CpuTopology(cores: [.init(id: 0, maxKhz: 2_000_000)])
        #expect(EngineTweaks().resolve(topo).params.nCtx == 4096)
        #expect(EngineTweaks().resolve(topo, totalRamBytes: 4 * gib).params.nCtx == 2048)
        #expect(EngineTweaks().resolve(topo, totalRamBytes: 6 * gib).params.nCtx == 3072)
        #expect(EngineTweaks().resolve(topo, totalRamBytes: Int64(6.5 * Double(gib))).params.nCtx == 3072)
        #expect(EngineTweaks().resolve(topo, totalRamBytes: 8 * gib).params.nCtx == 4096)
        #expect(EngineTweaks(contextTokens: 8192).resolve(topo, totalRamBytes: 4 * gib).params.nCtx == 8192)
    }

    // MARK: beyond the Kotlin tests

    @Test func engineParamsAndSamplingJSONUseTheKotlinKeys() {
        let p = EngineParams(nCtx: 2048, threads: 2, typeK: .q8_0, loadMode: .mmapMlock)
        #expect(p.threadsBatch == 2)
        let j = p.json
        #expect(j["typeK"] == 8)
        #expect(j["loadMode"] == 3)
        #expect(j["flashAttn"] == -1)
        #expect(Sampling(seed: 7).json["seed"] == 7)
        #expect(Sampling().json["seed"] == nil)
    }

    @Test func iosTopologyFromPerfLevelsIsOneFastGroupOverOneEfficiencyGroup() {
        // iPhone 13: 2 performance + 4 efficiency cores.
        let t = CpuTopology.fromPerfLevels(performance: 2, efficiency: 4)
        #expect(t.cores.count == 6)
        #expect(t.bigCores == [4, 5])
        #expect(EngineTweaks().resolve(t).params.threads == 2)
        #expect(CpuTopology.read().cores.count >= 1)
    }

    @Test func metricsParseReadsTheNativeJSON() throws {
        let m = try GenerationMetrics(json: #"{"promptTokens":10,"generatedTokens":5,"decodeTokPerSec":12.5,"stopReason":"eos","error":"x"}"#)
        #expect(m.promptTokens == 10 && m.generatedTokens == 5 && m.decodeTokPerSec == 12.5)
        #expect(m.ttftMs == -1 && m.stopReason == "eos" && m.error == "x")
    }
}
