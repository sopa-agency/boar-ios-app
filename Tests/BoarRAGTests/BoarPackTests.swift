import BoarCore
@testable import BoarRAG
import Foundation
import Testing

/// BOAR's guide and FAQ as one built-in pack, both languages, so BOAR can answer about itself (android BoarPackTest, t9 0225,
/// 0233, 0225 after-run): the assets are the app's own bundled copies (App/Resources/Data).
@Suite struct BoarPackTests {
    private static func asset(_ name: String) throws -> String {
        try String(contentsOf: Fixtures.root.appending(path: "App/Resources/Data/\(name)"), encoding: .utf8)
    }

    private let guides: [String: String]
    private let faq: String
    private let all: [BoarPack.Passage]

    init() throws {
        guides = ["en": try Self.asset("boar-guide-en.md"), "pt": try Self.asset("boar-guide-pt.md")]
        faq = try Self.asset("boar-faq.json")
        all = try BoarPack.passages(guides: guides, faqJson: faq)
    }

    /// A stand-in for the search model: one dimension per word, so the same words score high.
    private final class Vocab: @unchecked Sendable {
        var words: [String: Int] = [:]
        static let letters = try! NSRegularExpression(pattern: "\\p{L}+")
        func vec(_ t: String) -> [Float] {
            var v = [Float](repeating: 0, count: 4096)
            let s = t.lowercased()
            for m in Self.letters.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                let w = String(s[Range(m.range, in: s)!])
                if words[w] == nil { words[w] = words.count % 4096 }
                v[words[w]!] += 1
            }
            let n = v.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
            return n > 0 ? v.map { $0 / n } : v
        }
    }

    @Test func everyGuideSectionAndFaqEntryInBothLanguagesEachKnowingItsLanguage() {
        for lang in ["en", "pt"] {
            let sections = guides[lang]!.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.count
            #expect(all.filter { $0.lang == lang && $0.id.contains("-guide-") }.count >= sections, "\(lang)")
            #expect(all.filter { $0.lang == lang && $0.id.contains("-faq-") }.count == 10, "\(lang)")
        }
        #expect(all.allSatisfy { BoarPack.langOf($0.id) == $0.lang && $0.body.u16Count <= BoarPack.maxChars + 400 })
        #expect(all.count == Set(all.map(\.id)).count)
        #expect(all.contains { $0.title == "BOAR Guide · Privacy" } && all.contains { $0.title == "Guia do BOAR · Privacidade" })
        #expect(all.contains { $0.title == "BOAR FAQ · What is the BOAR app?" && $0.source == "BOAR FAQ, written by Amandita" })
        #expect(all.contains { $0.source == "FAQ do BOAR, escrito pela Amandita" })
    }

    @Test func aCrlfGuideSplitsItsHeadingLikeAnLfOne() {
        let lf = BoarPack.guide("en", markdown: guides["en"]!)
        let crlf = BoarPack.guide("en", markdown: guides["en"]!.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(crlf.map(\.title) == lf.map(\.title))
    }

    @Test func theFaqShipsOnlyTextCheckedAgainstRc3() throws {
        let root = try #require(JSONSerialization.jsonObject(with: Data(faq.utf8)) as? [String: Any])
        let entries = try #require(root["entries"] as? [[String: Any]])
        #expect(entries.allSatisfy { e in
            let c = e["checked"] as? String ?? ""
            return c.hasPrefix("ok for rc3") || c.hasPrefix("corrected for rc3")
        })
        // October's facts that rc3 changed are gone.
        for old in ["Qwen2.5-1.5B", "Executive Summary", "Resumo executivo", "copied over a cable", "copiados por cabo", "you can choose to share an evaluation"] {
            #expect(!faq.contains(old), "\(old)")
        }
        #expect(faq.contains("Amandita"))
    }

    @Test func aChangedTextReplacesItsPassageAnUnchangedOneIsntEmbeddedAgain() async throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        let vocab = Vocab()
        let embeds = Counter()
        let embed: (String) async throws -> [Float] = { embeds.bump(); return vocab.vec($0) }
        #expect(try await kb.syncBoar(all, embed: embed) == all.count)
        #expect(try await kb.syncBoar(all, embed: embed) == 0)
        let edited = try BoarPack.passages(
            guides: ["en": guides["en"]!.replacingOccurrences(of: "## Privacy\n", with: "## Privacy\nEdited line.\n"), "pt": guides["pt"]!], faqJson: faq
        )
        #expect(try await kb.syncBoar(edited, embed: embed) == 1)
        #expect(embeds.value == all.count + 1)
        // No search model yet: nothing stored, tried again later.
        let empty = try KnowledgeBase(db: SqliteDatabase.inMemory())
        #expect(try await empty.syncBoar(all) { _ in [] } == 0)
        #expect(try empty.chunkCount() == 0)
    }

    @Test func outOfTheGeneralSearchTheSeedCountAndTheDailyQuizFoundByItsOwnSearch() async throws {
        let kb = try KnowledgeBase(db: SqliteDatabase.inMemory())
        let vocab = Vocab()
        try kb.insertChunk(
            Chunk(chunkId: "wiki-min-privacy", docId: "wiki-min-privacy", title: "Privacy", body: "Privacy is the ability of an individual to keep information about themselves to themselves."),
            embedding: vocab.vec("Privacy is the ability of an individual to keep information")
        )
        _ = try await kb.syncBoar(all) { vocab.vec($0) }
        let q = "Does my data leave the phone? Privacy"
        #expect(try kb.semanticSearch(vocab.vec(q), limit: 50, minSimilarity: 0.0).allSatisfy { !$0.chunkId.hasPrefix(BoarPack.prefix) })
        #expect(try kb.lexicalSearch(q, queryVec: vocab.vec(q), limit: 50).allSatisfy { !$0.chunkId.hasPrefix(BoarPack.prefix) })
        #expect(try kb.seedChunkCount() == 1)
        #expect(try kb.seedArticles(seed: 1, limit: 100).allSatisfy { !$0.title.hasPrefix("BOAR") && !$0.title.hasPrefix("Guia") })
        let found = try kb.boarSearch(q, queryVec: vocab.vec(q), limit: 6)
        #expect(!found.isEmpty && found.allSatisfy { $0.chunkId.hasPrefix(BoarPack.prefix) && $0.source != nil })
    }

    @Test func theQuestionsLanguageFirstTheOtherWhenItHasNothingGood() {
        func c(_ id: String, _ sim: Double) -> Chunk { Chunk(chunkId: id, docId: id, title: id, body: "", similarity: sim) }
        let hits = [c("boar-en-faq-a", 0.80), c("boar-pt-faq-a", 0.62), c("boar-en-guide-b", 0.70)]
        #expect(BoarPack.rank(hits, lang: "pt").map(\.chunkId) == ["boar-pt-faq-a", "boar-en-faq-a", "boar-en-guide-b"])
        #expect(BoarPack.rank(hits, lang: "en").map(\.chunkId) == ["boar-en-faq-a", "boar-en-guide-b", "boar-pt-faq-a"])
        // A section only in English still answers a Portuguese question.
        #expect(BoarPack.rank([c("boar-en-guide-b", 0.70), c("boar-pt-faq-z", 0.40)], lang: "pt").map(\.chunkId) == ["boar-en-guide-b"])
    }

    @Test func questionsAboutBoarEnAndPtAndNotTheRest() {
        for q in [
            "What is BOAR?", "Does my data leave the phone?", "Does this app send telemetry?", "How do I set a PIN?", "Como funcionam os Arquivos locais?",
            "O que é a Pesquisa Profunda?", "Preciso comprar o token $BOAR?", "O app funciona sem internet?",
        ] { #expect(BoarPack.aboutBoar(q), "\(q)") }
        for q in ["What are the models of the atom?", "How do wild pigs live?", "How to pin a message on Telegram?", "Is the battery of an electric car recyclable?"] {
            #expect(!BoarPack.aboutBoar(q), "\(q)")
        }
    }

    @Test func boarSourcesAreRecognisedByTheirLabel() {
        #expect(BoarPack.isBoarSource("BOAR Guide") && BoarPack.isBoarSource("FAQ do BOAR, escrito pela Amandita"))
        #expect(!BoarPack.isBoarSource("BOAR Guide notes.pdf"))
    }

    @Test func javaStringHashCodeMatches() {
        #expect(BoarPack.javaHash("hello") == 99162322)
        #expect(BoarPack.javaHash("") == 0)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
