import Testing

@testable import BoarRAG

/// OwnFilesPortugueseTest.kt: a Portuguese question about the user's English file gets its English key terms, in
/// Personal Files and in the mixed search (Retriever.retrieveAll runs the English pass when the question looks
/// Portuguese). "resuma meu exame de sangue" and "meu colesterol está alto?" missed an English blood-test file: neither
/// read as Portuguese. Android's third test (lab terms the lexicon lacks: triglicerídeos, creatinina, receita médica)
/// needs PtLexicon's READINGS, which come with the Portuguese search port (rc3 block 5).
struct OwnFilesPortugueseTests {
    private var lex: PtLexicon.Lexicon { RagTextGoldenTests.lexicon }

    @Test func theFourPortugueseQuestionsReadAsPortugueseAndNameTheirEnglishTerms() {
        let cases: [(String, [String])] = [
            ("resuma meu exame de sangue", ["Blood test"]),
            ("quais são os resultados do meu exame de sangue?", ["Blood test"]),
            ("meu colesterol está alto?", ["Cholesterol"]),
            ("o que diz meu exame de sangue sobre vitamina D?", ["Blood test", "Vitamin D"]),
        ]
        for (q, names) in cases {
            #expect(PtLexicon.looksPortuguese(q), "\(q)")
            #expect(PtLexicon.englishNamesIn(q, lex) == names, "\(q)")
        }
    }

    @Test func theEnglishQuestionsStayEnglish() {
        for q in ["summarize my blood test", "is my cholesterol high?", "What is my resume about?"] {
            #expect(!PtLexicon.looksPortuguese(q), "\(q)")
        }
    }
}
