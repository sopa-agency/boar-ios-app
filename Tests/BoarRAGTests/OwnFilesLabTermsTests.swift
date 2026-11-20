import BoarRAG
import Testing

/// t9 0026 (blood test e): lab terms the lexicon lacks get their English names (the third test of OwnFilesPortugueseTest.kt).
@Suite struct OwnFilesLabTermsTests {
    private let lex = RagTextGoldenTests.lexicon

    @Test func labTermsTheLexiconLacks() {
        #expect(PtLexicon.englishNamesIn("meus triglicerídeos estão altos?", lex) == ["Triglyceride"])
        #expect(PtLexicon.englishNamesIn("minha creatinina está normal?", lex) == ["Creatinine"])
        #expect(PtLexicon.englishNamesIn("onde está minha receita médica?", lex) == ["Prescription"])
        // A recipe stays a recipe: bare "receita" isn't read as a prescription.
        #expect(!PtLexicon.englishNamesIn("receita de bolo de cenoura", lex).contains("Prescription"))
    }
}
