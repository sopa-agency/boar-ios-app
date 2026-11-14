import Testing
@testable import BoarModels

/// android `engine/models/StartLoadTest.kt`.
struct StartLoadTests {
    let gb: Int64 = 1_000_000_000
    /// An 8 GB phone: RED above 0.9 × 8 GB / 1.15 ≈ 6.26 GB of model, GREEN up to ≈ 4.52 GB.
    var ram: Int64 { 8 * gb }
    var small: StartLoad.Model { .init(id: "qwen2.5-1.5b", sizeBytes: 1 * gb) }
    var mid: StartLoad.Model { .init(id: "qwen3-4b", sizeBytes: 2_500_000_000) }
    var yellow: StartLoad.Model { .init(id: "lfm2.5-8b", sizeBytes: 4_800_000_000) }
    var red: StartLoad.Model { .init(id: "big-12b", sizeBytes: 7 * gb) }

    private func decide(_ active: StartLoad.Model?, _ installed: [StartLoad.Model], blocked: Set<String> = [], last: String? = nil,
                        anyway: Set<String> = []) -> StartLoad.Decision {
        StartLoad.decide(active: active, installed: installed, isBlocked: { blocked.contains($0) }, lastLoadedId: last,
                         totalRamBytes: ram, loadAnyway: anyway)
    }

    @Test func greenAndYellowModelsLoad() {
        #expect(decide(mid, [small, mid]) == .load(modelId: "qwen3-4b"))
        #expect(decide(yellow, [yellow]) == .load(modelId: "lfm2.5-8b"))
    }

    @Test func aRedModelAsksFirstUnlessTheUserChoseLoadAnyway() {
        #expect(decide(red, [small, red]) == .askRisky(modelId: "big-12b", onlyModel: false))
        #expect(decide(red, [red]) == .askRisky(modelId: "big-12b", onlyModel: true))
        #expect(decide(red, [small, red], anyway: ["big-12b"]) == .load(modelId: "big-12b"))
    }

    @Test func aRedModelAnEngineStreamsFromStorageLoadsWithoutAsking() {
        var streamed = red
        streamed.streamed = true
        #expect(decide(streamed, [small, streamed]) == .load(modelId: "big-12b"))
    }

    @Test func aRedModelOfAStreamingEngineTheUserMovedToBoarsEngineAsksFirst() {
        // BoarServices.startModel: streamed follows the engine that runs it now, not the model's engine tag.
        var onBoar = red
        onBoar.streamed = false
        #expect(decide(onBoar, [small, onBoar]) == .askRisky(modelId: "big-12b", onlyModel: false))
        #expect(StartLoad.risky(onBoar, totalRamBytes: ram))
        onBoar.streamed = true
        #expect(!StartLoad.risky(onBoar, totalRamBytes: ram))
    }

    @Test func unknownRamIsNeverRisky() {
        #expect(StartLoad.decide(active: red, installed: [red], isBlocked: { _ in false }, lastLoadedId: nil, totalRamBytes: 0,
                                 loadAnyway: []) == .load(modelId: "big-12b"))
    }

    @Test func aBlockedModelFallsBackToTheLastThatLoadedElseTheSmallest() {
        #expect(decide(yellow, [small, mid, yellow], blocked: ["lfm2.5-8b"], last: "qwen3-4b") == .fallback(blockedId: "lfm2.5-8b", modelId: "qwen3-4b"))
        #expect(decide(yellow, [mid, small, yellow], blocked: ["lfm2.5-8b"], last: "lfm2.5-8b") == .fallback(blockedId: "lfm2.5-8b", modelId: "qwen2.5-1.5b"))
        #expect(decide(yellow, [mid, small, yellow], blocked: ["lfm2.5-8b"]) == .fallback(blockedId: "lfm2.5-8b", modelId: "qwen2.5-1.5b"))
    }

    @Test func aBlockedModelWithEveryOtherBlockedLoadsNothing() {
        #expect(decide(yellow, [small, yellow], blocked: ["lfm2.5-8b", "qwen2.5-1.5b"]) == .noFallback(blockedId: "lfm2.5-8b", onlyModel: false))
    }

    @Test func theOnlyModelBlockedGetsTheDownloadMessage() {
        #expect(decide(yellow, [yellow], blocked: ["lfm2.5-8b"]) == .noFallback(blockedId: "lfm2.5-8b", onlyModel: true))
        // Load anyway doesn't override a block: that's Try again with less memory.
        #expect(decide(red, [red], blocked: ["big-12b"], anyway: ["big-12b"]) == .noFallback(blockedId: "big-12b", onlyModel: true))
    }

    @Test func noModelInstalled() {
        #expect(decide(nil, []) == .noModel)
        #expect(StartLoad.fallback(installed: [], isBlocked: { _ in false }, lastLoadedId: nil) == nil)
    }
}
