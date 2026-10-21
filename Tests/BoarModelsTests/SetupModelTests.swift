import Testing
@testable import BoarModels

/// Port of src/ui-android/setupModel.test.ts.
@Suite struct SetupModelTests {
    let gb = 1024.0 * 1024 * 1024

    func asset(_ id: String, _ tier: AnswerTier?, size: Int64 = 1) -> CatalogAsset {
        CatalogAsset(id: id, kind: .llm, label: id, filename: "models/\(id).gguf", sizeBytes: size, sha256: "", sourceUrl: "", license: "", description: "", required: false, answerTier: tier)
    }

    var big: CatalogAsset { asset("qwen3-4b", .default) }
    var small: CatalogAsset { asset("qwen2.5-1.5b", .compact) }
    var models: [CatalogAsset] { [big, small] }
    func ram(_ g: Double) -> Int64 { Int64(g * gb) }

    @Test func recommendsThe4BOnA12GBPhone_reads10_7GB() {
        #expect(SetupModel.recommended(models, totalRamBytes: ram(10.7)) == big)
    }

    @Test func recommendsThe1_5BOnAn8GBPhoneAndSmaller() {
        #expect(SetupModel.recommended(models, totalRamBytes: ram(7.3)) == small)
        #expect(SetupModel.recommended(models, totalRamBytes: ram(3.8)) == small)
    }

    @Test func recommendsThe1_5BWhenTheRAMCouldntBeRead() {
        #expect(SetupModel.recommended(models, totalRamBytes: 0) == small)
    }

    @Test func flagsThe4BUnder12GBNeverThe1_5B() {
        #expect(SetupModel.heavyForPhone(big, totalRamBytes: ram(7.3)))
        #expect(!SetupModel.heavyForPhone(big, totalRamBytes: ram(10.7)))
        #expect(!SetupModel.heavyForPhone(small, totalRamBytes: ram(3.8)))
    }

    @Test func doesntWarnWhenTheRAMCouldntBeRead() {
        #expect(!SetupModel.heavyForPhone(big, totalRamBytes: 0))
    }

    @Test func flagsA5GBCatalogModelEvenOnA12GBPhoneA1GBOneNowhereAbove4GB() {
        func other(_ bytes: Double) -> CatalogAsset { asset("other", nil, size: Int64(bytes * gb)) }
        #expect(SetupModel.heavyForPhone(other(5.2), totalRamBytes: ram(10.7)))
        #expect(!SetupModel.heavyForPhone(other(1.0), totalRamBytes: ram(7.3)))
    }

    @Test func takesTheUsersPickOverEverything() {
        #expect(SetupModel.toInstall(models, present: [small.id], totalRamBytes: ram(10.7), chosenId: big.id) == big)
    }

    @Test func keepsAModelAlreadyOnThePhoneInsteadOfDownloadingAnother() {
        #expect(SetupModel.toInstall(models, present: [small.id], totalRamBytes: ram(10.7)) == small)
    }

    @Test func fallsBackToTheRecommendedOne() {
        #expect(SetupModel.toInstall(models, present: [], totalRamBytes: ram(10.7)) == big)
        #expect(SetupModel.toInstall(models, present: [], totalRamBytes: ram(7.3)) == small)
    }

    @Test func fallsBackToTheFirstModelWhenNoTierMatches() {
        let only = [asset("x", nil)]
        #expect(SetupModel.recommended(only, totalRamBytes: ram(12))?.id == "x")
        #expect(SetupModel.recommended([], totalRamBytes: ram(12)) == nil)
    }

    @Test func compatibilityBuckets() {
        let ram8 = Int64(7.3 * gb)
        #expect(Compatibility.compute(sizeBytes: 986_048_768, deviceRamBytes: ram8) == .green)
        #expect(Compatibility.compute(sizeBytes: 2_497_281_120, deviceRamBytes: ram8) == .green)
        #expect(Compatibility.compute(sizeBytes: 4_000_000_000, deviceRamBytes: ram8) == .green)
        #expect(Compatibility.compute(sizeBytes: 5_500_000_000, deviceRamBytes: ram8) == .yellow)
        #expect(Compatibility.compute(sizeBytes: 6_500_000_000, deviceRamBytes: ram8) == .red)
        #expect(Compatibility.compute(sizeBytes: 1, deviceRamBytes: 0) == .unknown)
        #expect(Compatibility.green.value == "green")
    }
}
