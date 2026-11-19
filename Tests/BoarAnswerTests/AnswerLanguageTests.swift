import BoarCore
import BoarModels
import BoarRAG
import Foundation
import Testing
@testable import BoarAnswer

private typealias Lang = AnswerLanguage.Lang

/// Runs `body` with this language setting instead of the app's (tests run in parallel: the shared one is never touched).
/// The phone's language defaults to English, as on the JVM the Android tests run on.
private func with<T>(app: String? = nil, arm: Int = 1, phone: String = "en-US", _ body: () throws -> T) rethrows -> T {
    try AnswerLanguage.$scoped.withValue(AnswerLanguage.Setting(app: app, arm: arm, phone: phone), operation: body)
}

private let seawater = [Chunk(chunkId: "c1", docId: "d1", title: "Seawater", body: "Seawater is salty because rivers carry dissolved salts to the sea.")]

/// t9 0420 (adam: "send language fix. all prompts… this is important fix"): r4to's Portuguese line, back (AnswerLanguageTest.kt).
@Suite struct AnswerLanguageTests {
    @Test func aPortugueseQuestionGetsTheLineNextToItWithAndWithoutSourcesInBothPromptShapes() {
        with {
            let q = "Por que a água do mar é salgada?"
            let chat = RagPure.assembleChatMessages(q, seawater).last!.content
            #expect(chat.hasPrefix(q) && chat.hasSuffix("\n\n" + AnswerLanguage.ptWithSources))
            #expect(RagPure.assembleChatMessages(q, []).last!.content.hasSuffix("\n\n" + AnswerLanguage.ptNoSources))
            let plain = RagPure.assemblePrompt(q, seawater)
            #expect(plain.hasSuffix("Question: \(q)\n\n\(AnswerLanguage.ptWithSources)\n\nAnswer:"))
            // The system head (kept prefilled in the cache) is the same as for English.
            #expect(RagPure.assembleChatMessages("Why is seawater salty?", seawater).first!.content == RagPure.assembleChatMessages(q, seawater).first!.content)
        }
    }

    @Test func anEnglishQuestionsPromptIsExactlyAsBefore() {
        let q = "Why is seawater salty?"
        with {
            #expect(RagPure.assembleChatMessages(q, seawater).last!.content == q)
            #expect(!RagPure.assemblePrompt(q, seawater).contains("Responda"))
        }
        // Even in a Portuguese app: a clearly English question is answered in English.
        with(app: "pt") { #expect(RagPure.assembleChatMessages(q, seawater).last!.content == q) }
    }

    @Test func aFollowUpTakesTheConversationsLanguage() {
        // Android's Staged details step (not in this app) reads it from the real question; here the history decides
        // for a question that can't tell.
        let h = ConversationHistory(turns: [ConversationTurn(role: "user", text: "Por que o mar é salgado?"), ConversationTurn(role: "assistant", text: "Porque os rios…")])
        with { #expect(RagPure.assembleChatMessages("Everest?", seawater, history: h).last!.content.hasSuffix(AnswerLanguage.ptWithSources)) }
    }

    @Test func personalFilesInPortugueseSaysItsOwnLineAndDropHedgeKnowsIt() {
        with {
            let p = RagPure.assembleChatMessages("Qual é o meu tipo sanguíneo?", seawater, filesOnly: true).last!.content
            #expect(p.hasSuffix(AnswerLanguage.ptFilesOnly) && p.contains(PersonalFiles.notFoundPT))
            #expect(AnswerLanguage.ptFilesOnly.hasSuffix(": " + PersonalFiles.notFoundPT))
        }
        let a = PersonalFiles.notFoundPT + " Porém, seu exame mostra tipo O positivo [1], segundo o laudo de março de 2026 que você salvou."
        #expect(PersonalFiles.dropHedge(a) == "Seu exame mostra tipo O positivo [1], segundo o laudo de março de 2026 que você salvou.")
    }

    @Test func whichLanguageTheQuestionThenTheConversationsLastClearOneThenTheApp() {
        func check(_ q: String, _ earlier: [String], _ app: String?, _ want: Lang) {
            with { #expect(AnswerLanguage.of(q, earlier: earlier, app: app) == want, "\(q) / \(earlier) / \(app ?? "nil")") }
        }
        check("Quantos ossos tem o corpo humano?", [], nil, .pt)
        check("How many bones are in the human body?", [], "pt", .en)
        check("e por quê?", ["Por que o céu é azul?"], nil, .pt)
        check("and why?", ["Why is the sky blue?"], "pt", .en)
        check("Everest?", [], "pt", .pt)
        check("Everest?", [], "en", .en)
        check("26 km", ["Quanto é 26 milhas em km?"], nil, .pt)
    }

    @Test func r4tosLinesInAdamsWordingOfTheLanguage() {
        #expect(AnswerLanguage.ptWithSources == "Responda em Português, mesmo que as fontes estejam em inglês, e cite cada afirmação com o número da fonte, como [1].")
        #expect(AnswerLanguage.ptNoSources == "Responda em Português.")
    }

    @Test func theChatTitleFollowsTheChatsLanguageEnglishUnchanged() {
        with {
            #expect(Summarize.titleInput("Why is the sky blue?") == "\"Why is the sky blue?\"")
            #expect(Summarize.titleInput("Por que o céu é azul?") == "\"Por que o céu é azul?\"\n\n" + AnswerLanguage.ptNoSources)
        }
    }
}

/// t9 0420 item 5: the arms, bench only; English never moves (AnswerLanguageArmsTest).
@Suite struct AnswerLanguageArmsTests {
    private let src = [Chunk(chunkId: "c1", docId: "d1", title: "Seawater", body: "Seawater is salty.")]
    private let sys = "You are Boar, a concise offline research assistant. Answer in 2-3 short, direct sentences or a brief paragraph, no preamble. Do not default to a bulleted list or a single takeaway sentence followed by three bullet points — use bullets only when the content is genuinely a list of distinct items."
    private let rem = "Keep it short: 2-3 sentences. No lists unless the question asks for one."

    @Test func arm1KeepsTheEnglishStyleTextsArm2TheReminderInPortugueseArm3ThePromptToo() {
        let q = "Por que a água do mar é salgada?"
        func msgs(_ arm: Int) -> [PromptMessage] { with(arm: arm) { RagPure.assembleChatMessages(q, src, systemPrompt: sys, styleReminder: rem) } }
        #expect(msgs(1).last!.content.contains(rem) && msgs(1).first!.content.hasPrefix(sys))
        #expect(msgs(2).last!.content.contains("Seja breve: 2-3 frases.") && msgs(2).first!.content.hasPrefix(sys))
        #expect(msgs(3).first!.content.hasPrefix("Você é o Boar, um assistente de pesquisa offline e conciso."))
    }

    @Test func englishNeverMovesWhateverTheArm() {
        let en = with(arm: 1) { RagPure.assembleChatMessages("Why is seawater salty?", src, systemPrompt: sys, styleReminder: rem) }
        #expect(with(arm: 3) { RagPure.assembleChatMessages("Why is seawater salty?", src, systemPrompt: sys, styleReminder: rem) } == en)
    }

    @Test func everyStyleTextInPersonalitiesJsonHasItsPortuguese() throws {
        let json = try #require(JSONValue(jsonString: String(decoding: try BoarData.data(.personalities), as: UTF8.self)))
        let keys: Set<String> = ["systemPrompt", "styleReminder", "systemPromptSmall", "styleReminderSmall"]
        var texts: [String] = []
        func walk(_ v: JSONValue) {
            switch v {
            // Non-empty, as the Android test's regex reads them (the Custom style's prompt is "").
            case .object(let o): for (k, x) in o { if keys.contains(k), let s = x.stringValue { if !s.isEmpty { texts.append(s) } } else { walk(x) } }
            case .array(let a): a.forEach(walk)
            default: break
            }
        }
        walk(json)
        #expect(!texts.isEmpty)
        for t in texts { #expect(StylePt.of(t) != t, "\(t.prefix(40))") }
    }
}

/// LanguageArmRequestTest: a request's arm, 0 to 3 only (the runner sets it for the run and puts 1 back).
@Suite struct LanguageArmRequestTests {
    @Test func aRequestCarriesTheArm0To3OnlyAndArm0SendsNoLine() throws {
        #expect(try DeviceEval.parseRequest(#"{"requestId":"lang-a0","languageArm":0}"#).languageArm == 0)
        #expect(try DeviceEval.parseRequest(#"{"requestId":"lang-a2","languageArm":"2"}"#).languageArm == 2)
        #expect(try DeviceEval.parseRequest(#"{"requestId":"lang-none"}"#).languageArm == nil)
        #expect(with(arm: 0) { AnswerLanguage.line(.pt, withSources: true) } == nil)
        #expect(with(arm: 1) { AnswerLanguage.line(.pt, withSources: true) } == AnswerLanguage.ptWithSources)
        #expect(throws: EvalRequestError("\"languageArm\" must be 0, 1, 2 or 3")) { try DeviceEval.parseRequest(#"{"requestId":"x","languageArm":7}"#) }
    }
}

/// Validator C-1 to C-3 (t9 0010 item 5), R-D1 and R-D5 (t9 2226 item 6), and the Nov 14 detection measure kept as it was.
@Suite struct AnswerLanguageValidatorTests {
    @Test func spanishFrenchGermanAndAHolaGetNoPortugueseLineInAPortugueseAppToo() {
        with(app: "pt") {
            for q in ["hola", "¡Hola!", "¿Qué es la fotosíntesis?", "Cuál es la capital de Australia y por qué es importante",
                      "Pourquoi le ciel est bleu?", "Qu'est-ce que la photosynthèse?", "Bonjour", "Warum ist der Himmel blau?", "Wie funktioniert eine Impfung?", "Hallo"] {
                #expect(AnswerLanguage.of(q) == .other, "\(q)")
                #expect(AnswerLanguage.line(AnswerLanguage.of(q), withSources: true) == nil, "\(q)")
            }
            // Portuguese with a Spanish-looking name stays Portuguese.
            #expect(AnswerLanguage.of("Qual é a capital de El Salvador e de Los Angeles?") == .pt)
            #expect(AnswerLanguage.of("O que é o El Niño?") == .pt)
        }
    }

    @Test func systemFollowsThePhonesLanguageNotEnglish() {
        with(phone: "pt-BR") { #expect(AnswerLanguage.of("Napoleão") == .pt) }
        with(phone: "en-US") { #expect(AnswerLanguage.of("Napoleão") == .en) }
        // A setting chosen in the app still wins over the phone.
        with(app: "pt", phone: "en-US") { #expect(AnswerLanguage.of("Napoleão") == .pt) }
    }

    @Test func quotedWordsAndATranslateRequestDontMakeAnEnglishQuestionPortuguese() {
        with(app: "pt") {
            for q in ["Translate 'bom dia' to English", "Translate \"obrigado\" into English", "How do you say saudade in English?",
                      "What does 'cafuné' mean?", "What does the word \u{201C}gostoso\u{201D} mean?"] {
                #expect(AnswerLanguage.of(q) == .en, "\(q)")
            }
            // The other way: a Portuguese question about an English word stays Portuguese.
            #expect(AnswerLanguage.of("O que significa 'deadline' em inglês?") == .pt)
        }
    }

    @Test func anEnglishTitleAmongPortugueseWordsDoesntMakeTheQuestionEnglish() {
        // R-D1 (PortugueseSearchLowsTest).
        with(app: "pt") {
            for q in ["Resumo de The Matrix", "Letra de Let It Be"] { #expect(AnswerLanguage.of(q) == .pt, "\(q)") }
        }
        with { #expect(AnswerLanguage.of("What is the capital of Australia?") == .en) }
    }

    @Test func aForeignSentenceWithOneMarkerWordGetsNoPortugueseLine() {
        // R-D5 (PortugueseSearchLowsTest).
        with(app: "pt") {
            for q in ["Wie viele Einwohner hat Berlin", "Welche Hauptstadt hat Deutschland", "combien de temps dure un vol pour Paris", "Cómo funciona un motor de combustión"] {
                #expect(AnswerLanguage.of(q) == .other, "\(q)")
            }
            #expect(AnswerLanguage.of("gracias") == .pt)
        }
    }

    @Test func the40ShortQuestionsOfTheNov14MeasureReadAsTheyDid() {
        let cases: [(String, Lang?)] = [
            ("Por que o céu é azul?", .pt), ("Quantos ossos tem o corpo humano?", .pt), ("O que causa as marés?", .pt),
            ("Quem foi Santos Dumont?", .pt), ("e por quê?", .pt), ("quanto custa?", .pt), ("Capital da Austrália?", nil),
            ("Me explica a fotossíntese", nil), ("tem vacina pra dengue?", .pt), ("qual a altura do Everest", .pt), ("Napoleão", nil),
            ("como fazer pão", .pt), ("isso é perigoso?", .pt), ("e no Brasil?", .pt), ("Febre de 39 graus, o que faço?", .pt),
            ("Água do mar é salgada por quê", .pt), ("Quem descobriu o Brasil?", .pt), ("Diferença entre vírus e bactéria", .pt),
            ("melhor horário pra correr", nil), ("obrigado!", nil),
            ("Why is the sky blue?", .en), ("How many bones are in the human body?", .en), ("What causes tides?", .en),
            ("Who was Napoleon?", .en), ("and why?", .en), ("how much?", .en), ("Capital of Australia?", .en), ("Explain photosynthesis", .en),
            ("is there a dengue vaccine?", .en), ("Everest height", .en), ("Napoleon", nil), ("how to bake bread", .en), ("is it dangerous?", .en),
            ("and in Brazil?", .en), ("Fever of 39, what should I do?", .en), ("Why is seawater salty", .en), ("Who discovered Brazil?", .en),
            ("Virus vs bacteria", .en), ("best time to run", .en), ("thanks!", .en),
        ]
        #expect(cases.count == 40)
        for (q, want) in cases { #expect(AnswerLanguage.clear(q) == want, "\(q)") }
    }
}
