import Testing
@testable import BoarModels

/// Port of ModelOrderTest.kt.
@Suite struct ModelOrderTests {
    func m(_ id: String) -> CatalogAsset {
        CatalogAsset(id: id, kind: .llm, label: id, filename: "models/\(id).gguf", sizeBytes: 1, sha256: "", sourceUrl: "", license: "", description: "", required: false)
    }
    var items: [CatalogAsset] { ["a", "b", "c", "d", "e"].map(m) }
    let facts = ModelOrder.Facts(
        active: "c", onPhone: ["a", "c", "d"], downloading: ["e"], mine: ["d", "e"],
        lastUsed: ["a": 100, "c": 300, "d": 200], added: ["b": 5, "d": 9, "e": 7])

    func ids(_ sort: ModelOrder.Sort, _ filter: ModelOrder.Filter = .all, _ f: ModelOrder.Facts? = nil) -> [String] {
        ModelOrder.apply(items, sort: sort, filter: filter, facts: f ?? facts).map(\.id)
    }

    @Test func smartPutsTheActiveOneFirstThenDownloadsThenThePhonesModelsByLastUse() {
        #expect(ids(.smart) == ["c", "e", "d", "a", "b"])
    }

    @Test func lastUsedIsNewestFirstAndNeverUsedKeepCatalogOrderAtTheEnd() {
        #expect(ids(.lastUsed) == ["c", "d", "a", "b", "e"])
    }

    @Test func recentlyAddedIsNewestFirst() {
        #expect(ids(.added) == ["d", "e", "b", "a", "c"])
    }

    @Test func filters() {
        #expect(ids(.smart, .onPhone) == ["c", "d", "a"])
        #expect(ids(.smart, .downloading) == ["e"])
        #expect(ids(.smart, .mine) == ["e", "d"])
    }

    @Test func withNoTimesAtAllEverySortKeepsCatalogOrderAfterTheActiveOne() {
        let bare = ModelOrder.Facts(active: "c", onPhone: ["a", "c"])
        #expect(ids(.smart, .all, bare) == ["c", "a", "b", "d", "e"])
        #expect(ids(.lastUsed, .all, bare) == ["a", "b", "c", "d", "e"])
        #expect(ids(.added, .all, bare) == ["a", "b", "c", "d", "e"])
    }

    @Test func rawValuesAreAndroids() {
        #expect(ModelOrder.Sort(rawValue: "LAST_USED") == .lastUsed)
        #expect(ModelOrder.Filter(rawValue: "ON_PHONE") == .onPhone)
    }
}
