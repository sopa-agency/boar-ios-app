import BoarCore
@testable import BoarRAG
import Testing

/// Personal Files sends whole parts while they fit: context − prompt − answer − 128 (WholePassagesTest.kt). Four
/// ~500-token parts, a 300-token prompt and the style's Auto length fitted to each context the phones open.
struct WholePassagesTests {
    private func part(_ i: Int) -> Chunk {
        Chunk(chunkId: "p\(i)", docId: "d", title: "notes (part \(i)/4)",
              body: kotlinTrim(String(repeating: "Line \(i) of the notes with a figure 1,250 EUR. ", count: 44)))
    }
    private var parts: [Chunk] { (1...4).map(part) }
    private func fit(_ context: Int) -> Compress.Result {
        WholePassages.fit("figure", parts, contextSize: context, promptTokens: 300,
                          maxTokens: AppSettings.fitToContext(AppSettings.personalMaxTokens, openedContext: context))
    }

    @Test func a2048ContextKeepsTheTwoBestPartsWhole() {
        let r = fit(2048)
        #expect(r.chunks.map(\.chunkId) == ["p1", "p2"])
        #expect(r.chunks == Array(parts.prefix(2)))
    }

    @Test func a3072ContextKeepsThree() { #expect(fit(3072).chunks.map(\.chunkId) == ["p1", "p2", "p3"]) }

    @Test func a4096ContextKeepsAllFourWhole() {
        let r = fit(4096)
        #expect(r.chunks == parts)
        #expect(r.tokensBefore == r.tokensAfter)
    }

    @Test func theBudgetIsContextMinusPromptAnswerAndMargin() {
        #expect(WholePassages.budget(contextSize: 4096, promptTokens: 300, maxTokens: 768) == 4096 - 300 - 768 - 128)
    }

    @Test func aSinglePartTooBigAloneIsCompressedToTheRoomLeft() {
        let big = Chunk(chunkId: "big", docId: "d", title: "ledger", body: (1...120).map { "Entry \($0) paid on day \($0) of the month." }.joined(separator: " "))
        let room = WholePassages.budget(contextSize: 2048, promptTokens: 300, maxTokens: 548)
        let r = WholePassages.fit("entry 42", [big], contextSize: 2048, promptTokens: 300, maxTokens: 548)
        #expect(r.chunks.count == 1)
        #expect(r.chunks[0].body.utf16.count < big.body.utf16.count)
        #expect(r.tokensAfter <= room, "\(r.tokensAfter) > \(room)")
    }

    @Test func partsThatFitAreSentUnchangedAndInRankOrder() {
        let small = [Chunk(chunkId: "b", docId: "d", title: "B", body: "Second."), Chunk(chunkId: "a", docId: "d", title: "A", body: "First.")]
        #expect(WholePassages.fit("x", small, contextSize: 2048, promptTokens: 300, maxTokens: 548).chunks == small)
    }
}
