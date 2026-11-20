import BoarRAG
import Testing

/// t9 0110 item 6, point 2: "na natureza" is "in the wild", not the article Nature (InTheWildTest.kt).
@Suite struct InTheWildTests {
    private let lexicon = RagTextGoldenTests.lexicon

    @Test func inTheWildNeverSearchesNature() {
        for q in ["Como purificar água na natureza, passo a passo?", "Como sobreviver em meio à natureza?", "Acampar em plena natureza é seguro?",
                  "Como achar comida no meio da natureza?"] {
            #expect(!PtLexicon.englishNamesIn(q, lexicon).contains("Nature"), "\(q)")
        }
    }

    @Test func natureItselfStillDoes() {
        #expect(PtLexicon.englishNamesIn("O que é a natureza?", lexicon) == ["Nature"])
        #expect(PtLexicon.englishNamesIn("Proteção da natureza no Brasil", lexicon) == ["Nature", "Brazil"])
    }
}
