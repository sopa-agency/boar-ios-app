import Testing
@testable import BoarAnswer

/// android `engine/answer/SourceGroupsTest.kt`.
struct SourceGroupsTests {
    private struct P: Equatable {
        var doc: String
        var score: Double?
        var body: String
    }

    private func group(_ ps: [P]) -> SourceGroups.Grouped<P> {
        SourceGroups.group(ps, key: { $0.doc }, score: { $0.score }) { g in
            var first = g[0]
            first.body = g.map(\.body).joined(separator: " | ")
            return first
        }
    }

    @Test func mergesPassagesOfOneArticleAndSortsByBestScore() {
        // Seen on the X6: Methane 85%, Methane clathrate 76%, Methane 85%, Methane clathrate 74%; 86% under 78%.
        let g = group([P(doc: "clathrate", score: 0.76, body: "c1"), P(doc: "methane", score: 0.85, body: "m1"),
                       P(doc: "clathrate", score: 0.74, body: "c2"), P(doc: "methane", score: 0.86, body: "m2")])
        #expect(g.items == [P(doc: "methane", score: 0.86, body: "m2 | m1"), P(doc: "clathrate", score: 0.76, body: "c1 | c2")])
        #expect(g.renumber == [1: 2, 2: 1, 3: 2, 4: 1])
    }

    @Test func unknownScoresGoLastAndTiesKeepTheirOrder() {
        let g = group([P(doc: "a", score: nil, body: "a"), P(doc: "b", score: 0.5, body: "b"), P(doc: "c", score: 0.5, body: "c")])
        #expect(g.items.map(\.doc) == ["b", "c", "a"])
    }

    @Test func samePageFromTwoPacksIsOneArticle() {
        let vital = SourceGroups.articleKey(source: "Wikipedia — https://en.wikipedia.org/wiki/Methane", docId: "pack:wiki-vital5:Methane", title: "Methane")
        let big = SourceGroups.articleKey(source: "Wikipedia — https://en.wikipedia.org/wiki/Methane (CC BY-SA 4.0)", docId: "pack:enwiki:a42", title: "Methane")
        #expect(vital == big)
        #expect(SourceGroups.articleKey(source: nil, docId: "doc-7", title: "Notes") == "doc-7")
        #expect(SourceGroups.articleKey(source: "My notes", docId: nil, title: "Notes") == "Notes")
    }

    @Test func renumbersCitations() {
        let map = [1: 2, 2: 1, 3: 2, 4: 1]
        #expect(SourceGroups.renumber("Methane [2][4] traps heat [1]; ice [3].", map: map) == "Methane [1] traps heat [2]; ice [2].")
        #expect(SourceGroups.renumber("Out of range [9] stays.", map: map) == "Out of range [9] stays.")
        #expect(SourceGroups.renumber("Same [1] [2]", map: [1: 1, 2: 2]) == "Same [1] [2]")
    }
}
