import Foundation
import Testing
@testable import BoarModels

/// Reads the real exported catalog (scripts/export-native-data.mjs), bundled in BoarModels, so a mismatch with manifest.ts fails here.
@Suite struct CatalogTests {
    let catalog = try! Catalog.bundled()

    @Test func answerModelsAreTheDefaultThenTheCompactTier() {
        #expect(catalog.defaultAnswerModel.id == "qwen3-4b-instruct-2507-q4km")
        #expect(catalog.compactAnswerModel.id == "qwen3-1.7b-q4km")
        #expect(catalog.answerModels.map(\.answerTier) == [.default, .compact])
    }

    @Test func setupOffersEverySuggestedModelSmallestFirstNeverAHiddenOne() {
        let ids = catalog.setupModels.map(\.id)
        #expect(ids.first == "qwen2.5-1.5b-instruct-q4km")
        #expect(catalog.answerModels.allSatisfy { ids.contains($0.id) })
        #expect(!ids.contains("phi-3.5-mini-instruct-q4km"))
        #expect(catalog.setupModels.map(\.sizeBytes) == catalog.setupModels.map(\.sizeBytes).sorted())
    }

    @Test func requiredModelsAreTheEmbeddingModelPlusTheDefaultAnswerModel() {
        #expect(Set(catalog.requiredModels.map(\.kind)) == [.embedding, .llm])
    }

    @Test func everyAssetHasAPinnedSha256AndAFileUnderTheAppsFolder() {
        for it in catalog.models {
            #expect(it.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, "\(it.id)")
            #expect(!it.filename.trimmingCharacters(in: .whitespaces).isEmpty && !it.filename.hasPrefix("/"), "\(it.id)")
        }
    }

    @Test func everyTierPointsAtCorpusAssetsThatExist() {
        let corpus = Set(catalog.corpusCatalog.map(\.id))
        for t in catalog.tiers { for p in t.corpusPackIds { #expect(corpus.contains(p), "\(t.id): \(p)") } }
    }

    @Test func architectureIsOptionalSoOlderCatalogsAndSavedModelsStillParse() throws {
        #expect(catalog.models.allSatisfy { $0.architecture == nil })
        let asset = #"{"id":"hf-a-b","kind":"llm","label":"b","filename":"models/hf-a-b.gguf","sizeBytes":1,"sha256":"","sourceUrl":"u","license":"l","description":"d","required":false}"#
        #expect(try JSONDecoder().decode(CatalogAsset.self, from: Data(asset.utf8)).architecture == nil)
        let withArch = String(asset.dropLast()) + #","architecture":"lfm2moe"}"#
        #expect(try JSONDecoder().decode(CatalogAsset.self, from: Data(withArch.utf8)).architecture == "lfm2moe")
    }

    @Test func phi35MiniIsNoLongerSuggestedAndNothingSetupNeedsIsHidden() {
        #expect(catalog.models.filter(\.hidden).map(\.id) == ["phi-3.5-mini-instruct-q4km"])
        for m in catalog.requiredModels + catalog.answerModels { #expect(!m.hidden, "\(m.id)") }
    }

    @Test func parsesCuratedCapabilitiesAndDefaults() throws {
        let four = catalog.defaultAnswerModel
        #expect(four.capabilities?.usesChatTemplate == true)
        #expect(four.capabilities?.roles == ["general", "fast"])
        #expect(four.shortName == "Qwen3 4B")
        let lfm = try #require(catalog.byId("lfm2.5-8b-a1b-q4km"))
        #expect(lfm.capabilities == nil && !lfm.hidden && !lfm.bundled && lfm.requires.isEmpty)
        #expect(catalog.tier("full")?.corpusPackIds == ["corpus-standard", "corpus-full"])
        #expect(catalog.storageBudgetBytes == 50_000_000_000)
    }

    @Test func ignoresUnknownKeysAndRejectsUnknownKinds() throws {
        let ok = #"{"storageBudgetBytes":1,"ramBudgetBytes":2,"extra":true,"tiers":[],"models":[{"id":"a","kind":"corpus","label":"A","filename":"corpus/a","sizeBytes":3,"sha256":"","sourceUrl":"","license":"x","description":"","required":false,"future":1}]}"#
        #expect(try Catalog.parse(ok).models.first?.kind == .corpus)
        #expect(throws: (any Error).self) { try Catalog.parse(ok.replacingOccurrences(of: "\"corpus\"", with: "\"video\"")) }
    }

    @Test func allBundledDataFilesAreValidJSON() throws {
        for f in BoarData.File.allCases {
            let obj = try JSONSerialization.jsonObject(with: BoarData.data(f))
            #expect(obj is [String: Any] || obj is [Any], "\(f)")
        }
    }
}
