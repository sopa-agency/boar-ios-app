import BoarCore
import BoarRAG
import Foundation
import Testing

/// Context compression and sentence splitting must match the TypeScript engine on real corpus passages.
@Suite struct CompressGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("rag-pure.json") }

    private func assertSame(_ label: String, _ expected: JSONValue, _ got: Compress.Result) {
        #expect(got.keptIndices == expected["keptIndices"]!.arr.map(\.int), "\(label) kept")
        #expect(got.chunks.map(\.body) == expected["chunks"]!.arr.map(goldenChunk).map(\.body), "\(label) bodies")
        #expect(got.tokensBefore == expected["tokensBefore"]!.int, "\(label) tokensBefore")
        #expect(got.tokensAfter == expected["tokensAfter"]!.int, "\(label) tokensAfter")
    }

    @Test func sentencesSplitTheSameWay() throws {
        let cases = try req(g["sentences"]).arr
        #expect(cases.count == 41)
        for o in cases { #expect(Compress.splitSentences(o["t"]!.str!) == o["out"]!.arr.map { $0.str! }, "t=\(o["t"]!.str!)") }
    }

    @Test func compressionKeepsTheSameSentencesForEveryQuestion() throws {
        let cases = try req(g["compress"]).arr
        #expect(cases.count == 36)
        for o in cases {
            let q = o["q"]!.str!
            assertSame("q=\(q) (\(o["taskType"]!.str!))", o["out"]!, Compress.forAnswer(q, o["chunks"]!.arr.map(goldenChunk), taskType: o["taskType"]!.str!))
        }
    }

    @Test func aPinnedPassageComesFirstWhateverItsScore() throws {
        let o = try req(g["compressPinned"])
        let got = Compress.compress(o["q"]!.str!, o["chunks"]!.arr.map(goldenChunk), tokenBudget: 200, pinned: Set(o["pinned"]!.arr.map { $0.str! }))
        assertSame("pinned", o["out"]!, got)
    }
}
