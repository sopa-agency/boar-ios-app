import BoarRouting
import Testing

/// AnswerPathTest.kt: small talk never starts Deep Research or the router.
struct AnswerPathTests {
    private func path(_ q: String, deep: Bool, about: Bool = false, adaptive: Bool = false) -> AnswerPath {
        AnswerPath.of(deepResearch: deep, aboutConversation: about, adaptive: adaptive, smallTalk: AnswerPath.isSmallTalk(q))
    }

    @Test func smallTalkNeverStartsADeepResearchOrTheRouter() {
        for q in ["hi", "oi", "hola", "thanks", "bom dia", "hey, what's up?", "obrigado!", "buenos días"] {
            #expect(path(q, deep: true) == .pipeline, "\(q)")
            #expect(path(q, deep: false, adaptive: true) == .pipeline, "\(q)")
        }
    }

    @Test func aRealQuestionKeepsItsPathGreetingOrNot() {
        for q in ["Why is Kyoto historically important?", "hi, can you compare Paris and Rome?", "oi, compare X e Y"] {
            #expect(path(q, deep: true) == .research, "\(q)")
            #expect(path(q, deep: false, adaptive: true) == .adaptive, "\(q)")
            #expect(path(q, deep: false) == .pipeline, "\(q)")
        }
    }

    @Test func aRecapStillGoesToDeepResearchsRecap() {
        #expect(path("Summarize what we talked about so far.", deep: false, about: true, adaptive: true) == .recap)
        #expect(path("Summarize what we talked about so far.", deep: true, about: true) == .research)
    }

    @Test func greetingsInPortugueseSpanishFrenchAndGermanAreSmallTalk() {
        for q in ["oi", "oii", "oie", "olá", "e aí", "fala aí", "boa noite", "tudo bem?", "beleza", "valeu demais", "tchau", "até mais",
                  "hola", "qué tal", "buenas noches", "de nada", "hasta luego", "adiós", "salut", "ça va", "bonjour", "hallo", "guten Morgen",
                  "tschüss", "thx", "ty", "cheers", "sounds good", "ttyl", "heyyy", "Olá!"] {
            #expect(AnswerPath.isSmallTalk(q), "\(q)")
        }
    }

    @Test func aGreetingWithAQuestionOrAWordThatCanStartARequestIsNotSmallTalk() {
        for q in ["oi, compare X e Y", "hola, resume este PDF", "bonjour, qui était Napoléon?", "show", "later", "bitte",
                  "vale", "top", "boa tarde, qual a capital da Austrália?"] {
            #expect(!AnswerPath.isSmallTalk(q), "\(q)")
        }
    }
}
