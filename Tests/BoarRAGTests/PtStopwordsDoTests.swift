import BoarRAG
import Testing

/// PtStopwordsDoTest.kt, validator P-C6 (t9 0435): a Portuguese question with "do" kept every Portuguese function word
/// as a keyword.
@Suite struct PtStopwordsDoTests {
    private func words(_ q: String) throws -> Set<String> {
        Set(try #require(RagPure.buildLexicalQuery(q)).terms.flatMap(\.forms))
    }

    @Test func portugueseQuestionsWithDoDropTheirFunctionWords() throws {
        let moncoes = try words("Como as monções se formam e por que importam para a agricultura do Brasil")
        for w in ["como", "se", "por", "que", "para"] { #expect(!moncoes.contains(w), "\(w) in \(moncoes)") }
        #expect(moncoes.contains { $0.hasPrefix("agricultur") } && moncoes.contains { $0.hasPrefix("brasil") })
        let sol = try words("Qual o tamanho do Sol para a Terra")
        for w in ["qual", "para"] { #expect(!sol.contains(w), "\(w) in \(sol)") }
    }

    @Test func englishQuestionsKeepTheirKeywords() throws {
        #expect(try words("What is DOS?").contains("dos"))
        #expect(try words("Who is Uma Thurman?").contains("uma"))
    }
}
