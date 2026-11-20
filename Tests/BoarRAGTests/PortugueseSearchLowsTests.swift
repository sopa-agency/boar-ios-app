import BoarRAG
import Testing

private typealias Lang = AnswerLanguage.Lang

/// Runs `body` with this app language instead of the shared one (tests run in parallel).
private func with<T>(app: String?, _ body: () throws -> T) rethrows -> T {
    try AnswerLanguage.$scoped.withValue(AnswerLanguage.Setting(app: app, arm: 1, phone: "en-US"), operation: body)
}

/// The validator's gate of eaa0161c, part D (t9 2226 item 6): R-D1 to R-D5 (PortugueseSearchLowsTest.kt).
@Suite struct PortugueseSearchLowsTests {
    private let lx = RagTextGoldenTests.lexicon
    private func names(_ q: String) -> [String] { PtLexicon.englishNamesIn(q, lx) }

    @Test func anEnglishTitleAmongPortugueseWordsDoesntMakeTheQuestionEnglish() {
        with(app: "pt") {
            for q in ["Resumo de The Matrix", "Letra de Let It Be"] { #expect(AnswerLanguage.of(q) == Lang.pt, "\(q)") }
            #expect(AnswerLanguage.of("What is the capital of Australia?") == Lang.en)
        }
    }

    @Test func humanNatureAndManInNatureKeepTheirArticles() {
        #expect(names("Existe maldade na natureza humana?").contains("Human nature"))
        #expect(names("Qual o papel do homem na natureza?").contains("Nature"))
        #expect(!names("Como purificar água na natureza, passo a passo?").contains("Nature"))
    }

    @Test func ceuAzulIsTheSkysLightOnlyInAWhyOrHowQuestion() {
        #expect(names("Por que o céu é azul?") == ["Diffuse sky radiation"])
        for q in ["Como fazer um céu azul no Photoshop?", "O que é o Céu Azul Futebol Clube?"] { #expect(!names(q).contains("Diffuse sky radiation"), "\(q)") }
    }

    @Test func englishAcronymsKeepTheirKeywordPortugueseQuestionsStillDropFunctionWords() throws {
        for (q, term) in [("What is DOS?", "dos"), ("What is Na?", "na"), ("What is a SEM?", "sem"), ("Who is Uma Thurman?", "uma")] {
            #expect(try #require(RagPure.buildLexicalQuery(q)).match.contains("\"\(term)\""), "\(q)")
        }
        #expect(!(try #require(RagPure.buildLexicalQuery("Como as monções se formam, e por que importam para a agricultura")).match.contains("\"para\"")))
    }

    @Test func aForeignSentenceWithOneMarkerWordGetsNoPortugueseLine() {
        with(app: "pt") {
            for q in ["Wie viele Einwohner hat Berlin", "Welche Hauptstadt hat Deutschland", "combien de temps dure un vol pour Paris", "Cómo funciona un motor de combustión"] {
                #expect(AnswerLanguage.of(q) == Lang.other, "\(q)")
            }
            #expect(AnswerLanguage.of("gracias") == Lang.pt)
        }
    }
}
