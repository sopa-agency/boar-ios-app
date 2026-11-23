import BoarModels
import Testing

@testable import BoarAnswer

/// android `engine/models/AnsweringModelTest.kt`: the model the chat answers with and its header names, one rule for both.
struct AnsweringModelTests {
    let qwen4b = StartLoad.Model(id: "qwen3-4b", sizeBytes: 2_500_000_000)
    let gemma = StartLoad.Model(id: "gemma-4-e4b", sizeBytes: 5_000_000_000)
    let bigBoar = StartLoad.Model(id: "qwen3.6-35b-a3b", sizeBytes: 20_000_000_000, streamed: true)
    let blocked: Set<String> = ["qwen3-4b"]

    /// What BoarServices lists: a model whose file is whole.
    private func installed(_ files: (StartLoad.Model, Int64)...) -> [StartLoad.Model] {
        files.filter { m, len in StartLoad.complete(isFile: true, lengthBytes: len, expectedBytes: m.sizeBytes) }.map(\.0)
    }

    @Test func aDownloadInProgressIsntInstalled() {
        #expect(!StartLoad.complete(isFile: true, lengthBytes: 1_200_000_000, expectedBytes: gemma.sizeBytes))
        #expect(StartLoad.complete(isFile: true, lengthBytes: gemma.sizeBytes, expectedBytes: gemma.sizeBytes))
        #expect(!StartLoad.complete(isFile: false, lengthBytes: 0, expectedBytes: gemma.sizeBytes))
        // A model of unknown size (copied by hand) counts once its file is there.
        #expect(StartLoad.complete(isFile: true, lengthBytes: 123, expectedBytes: 0))
    }

    @Test func thePickAnswersWhileAnotherModelDownloads() {
        let phone = installed((qwen4b, qwen4b.sizeBytes), (gemma, 1_200_000_000))
        #expect(StartLoad.answering(active: qwen4b, installed: phone, isBlocked: { _ in false }, lastLoadedId: nil) == qwen4b)
    }

    @Test func aHeldBackPickNeverFallsBackToAHalfDownloadedModel() {
        let phone = installed((qwen4b, qwen4b.sizeBytes), (gemma, 1_200_000_000))
        #expect(StartLoad.answering(active: qwen4b, installed: phone, isBlocked: { blocked.contains($0) }, lastLoadedId: nil) == nil)
    }

    @Test func aHeldBackPickNeverFallsBackToBigBoarOnItsOwnEvenAsTheLastOneLoaded() {
        let small = StartLoad.Model(id: "qwen3-1.7b", sizeBytes: 1_100_000_000)
        let phone = [qwen4b, small, bigBoar]
        #expect(StartLoad.answering(active: qwen4b, installed: phone, isBlocked: { blocked.contains($0) }, lastLoadedId: bigBoar.id) == small)
        #expect(StartLoad.answering(active: qwen4b, installed: [qwen4b, bigBoar], isBlocked: { blocked.contains($0) }, lastLoadedId: bigBoar.id) == nil)
    }

    @Test func bigBoarAnswersWhenTheUserPicksItAndNotOnceItsLabIsOff() {
        #expect(StartLoad.answering(active: bigBoar, installed: [qwen4b, bigBoar], isBlocked: { _ in false }, lastLoadedId: nil) == bigBoar)
        // Lab off: its model leaves the catalog, so the pick is the catalog's again.
        #expect(StartLoad.answering(active: qwen4b, installed: [qwen4b], isBlocked: { _ in false }, lastLoadedId: bigBoar.id) == qwen4b)
    }

    @Test func theHeaderNamesTheModelAnArrowWhileAnotherOneWrites() {
        #expect(HeaderModel.label(answeringNow: false, answeringModel: nil, phoneModel: "Qwen3-4B") == "Qwen3-4B")
        #expect(HeaderModel.label(answeringNow: true, answeringModel: "Qwen3-1.7B", phoneModel: "Qwen3-4B") == "→ Qwen3-1.7B")
        // The arrow only while answering: after it, back to the source.
        #expect(HeaderModel.label(answeringNow: false, answeringModel: "Gemma", phoneModel: "Qwen3-4B") == "Qwen3-4B")
        #expect(HeaderModel.label(answeringNow: false, answeringModel: nil, phoneModel: nil) == nil)
    }
}
