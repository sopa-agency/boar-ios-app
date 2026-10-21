import Testing
@testable import BoarCore

@Suite struct TweakPresetsTests {
    /// Dimensity 8300 (X6 Pro): 4 little, then 1 prime + 3 big.
    let x6 = CpuTopology(cores:
        (0..<4).map { CpuTopology.Core(id: $0, maxKhz: 2_200_000) } + [CpuTopology.Core(id: 4, maxKhz: 3_350_000)]
        + (0..<3).map { CpuTopology.Core(id: 5 + $0, maxKhz: 3_200_000) })

    @Test func boarsPathIsAuto() {
        #expect(TweakPreset.path.applyTo(EngineTweaks()).isAuto)
        #expect(TweakPreset.of(EngineTweaks()) == .path)
    }

    @Test func eachPresetIsRecognisedAfterItIsApplied() {
        for p in TweakPreset.allCases { #expect(TweakPreset.of(p.applyTo(EngineTweaks())) == p) }
    }

    @Test func aPresetKeepsTheDevicesCpuBuild() {
        let mine = EngineTweaks(cpuBuild: "armv8.6_1")
        for p in TweakPreset.allCases {
            #expect(p.applyTo(mine).cpuBuild == "armv8.6_1")
            #expect(TweakPreset.of(p.applyTo(mine)) == p)
        }
    }

    @Test func aKnobChangedByHandMakesItCustom() {
        var t = TweakPreset.run.applyTo(EngineTweaks())
        t.threads = 3
        #expect(TweakPreset.of(t) == nil)
        #expect(TweakPreset.of(EngineTweaks(kvCache: .q8_0)) == nil)
    }

    @Test func runBoarRunKeepsAutosThreadsOnTheFastCoresAndAddsNoSlowOnes() {
        let t = TweakPreset.run.applyTo(EngineTweaks())
        let r = t.resolve(x6)
        #expect(r.params.threads == 4)
        #expect(r.params.cpus == "4,5,6,7")
        #expect(r.params.strictCpu)
        #expect(r.params.loadMode == .mmapMlock)
        #expect(t.stageTimeoutMs(nPredict: 1024) == nil)
        #expect(r.notes.isEmpty)
    }

    @Test func theGentlePresetsResolveWithoutClamping() {
        for p in [TweakPreset.forage, .cool] {
            let t = p.applyTo(EngineTweaks())
            let r = t.resolve(x6)
            #expect(r.notes.isEmpty)
            #expect(r.params.nCtx == 2048)
            #expect(t.thinkingEnabled == false)
            #expect(t.stageTimeoutMs(nPredict: 1024) == 300_000)
        }
        #expect(TweakPreset.cool.applyTo(EngineTweaks()).resolve(x6).params.threads == 1)
    }

    @Test func presetKeysAndEmojiAreStable() {
        #expect(TweakPreset.allCases.map(\.key) == ["run", "path", "forage", "cool"])
        #expect(TweakPreset.allCases.map(\.emoji) == ["🐗", "🌲", "🍄", "🧊"])
    }
}
