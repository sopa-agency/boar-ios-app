import BoarCore
import BoarRAG
import Foundation
import Testing

/// Portuguese lexicon, identifiers, "why" reordering and duplicate removal must match the TypeScript engine.
@Suite struct RagTextGoldenTests {
    let g: JSONValue

    init() throws { g = try Fixtures.golden("rag-pure.json") }

    /// The app's real 173k-name lexicon (assets/lexicon/pt-en.json), in file order, loaded once for all tests.
    static let lexicon: PtLexicon.Lexicon = {
        do { return try PtLexicon.Lexicon(jsonData: Fixtures.data(Fixtures.asset("lexicon/pt-en.json"))) }
        catch { fatalError("pt-en lexicon: \(error)") }
    }()

    @Test func portugueseDetectionNamesAndKeysMatchOn30Questions() throws {
        let cases = try req(g["ptLexicon"]).arr
        #expect(cases.count == 30)
        #expect(Self.lexicon.count > 100_000)
        for o in cases {
            let q = o["q"]!.str!
            #expect(PtLexicon.looksPortuguese(q) == o["looksPt"]!.flag, "looksPortuguese(\(q))")
            #expect(PtLexicon.englishNamesIn(q, Self.lexicon) == o["names"]!.arr.map { $0.str! }, "englishNamesIn(\(q))")
            #expect(PtLexicon.normalizeKey(q) == o["key"]!.str, "normalizeKey(\(q))")
        }
    }

    @Test func portugueseSingulars() throws {
        for c in try req(g["singularsPt"]).arr { #expect(PtLexicon.singularsPt(c["w"]!.str!) == c["out"]!.arr.map { $0.str! }) }
    }

    @Test func standardsNamedByNumber() throws {
        for c in try req(g["identifiers"]).arr { #expect(Identifiers.identifiersIn(c["q"]!.str!) == c["out"]!.arr.map { $0.str! }) }
        for o in try req(g["titleHasId"]).arr {
            #expect(Identifiers.titleHasIdentifier(o["t"]!.str!, o["id"]!.str!) == o["out"]!.flag, "\(o["t"]!.str!) ~ \(o["id"]!.str!)")
        }
    }

    @Test func whyQuestionsAreRecognizedAndTheirPassagesReordered() throws {
        let intents = try req(g["explainIntent"]).arr
        #expect(intents.count == 62)
        for c in intents { #expect(Explain.hasExplainIntent(c["q"]!.str!) == c["out"]!.flag, "EXPLAIN_INTENT(\(c["q"]!.str!))") }
        let o = try req(g["explaining"])
        let got = Explain.explainingFirst(o["items"]!.arr.map(goldenChunk), RagPure.buildLexicalQuery(o["q"]!.str!)!.terms)
        let exp = o["out"]!.arr.map(goldenChunk)
        #expect(got.map(\.chunkId) == exp.map(\.chunkId))
        #expect(got.map(\.score) == exp.map(\.score))
    }

    @Test func duplicatePassagesAreRemovedTheSameWay() throws {
        for o in try req(g["dedupe"]).arr {
            #expect(Dedupe.dedupeArticleCopies(o["chunks"]!.arr.map(goldenChunk)).map(\.chunkId) == o["out"]!.arr.map { $0.str! })
        }
        for o in try req(g["containedShare"]).arr {
            #expect(abs(Dedupe.containedShare(o["a"]!.str!, o["b"]!.str!) - o["out"]!.dbl) <= 1e-12)
        }
    }

    // MARK: beyond the Kotlin test

    @Test func theLexiconKeepsFileOrderAndTheLastValueOfARepeatedKey() throws {
        let lex = try PtLexicon.Lexicon(jsonData: Data(#"{"b": "Two", "a": "One", "b": "Deux", "cão": "Dog 🐕"}"#.utf8))
        #expect(lex.keys == ["b", "a", "c\u{00E3}o"])
        #expect(lex.values == ["Deux", "One", "Dog \u{1F415}"])
        #expect(lex["a"] == "One")
        #expect(lex["zzz"] == nil)
    }
}
