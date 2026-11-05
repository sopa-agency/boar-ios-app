import BoarRouting
import Testing

@testable import BoarAnswer

/// android CoHazardPtEsTest.kt: Boar Cohazard in Portuguese and Spanish (draft answers), through LabTools.coHazard as the
/// lab runs it.
struct CoHazardPtEsTests {
    private let pt = [
        "Posso usar aquecedor a gás dentro da barraca?",
        "gerador na garagem fechada",
        "Posso ligar o gerador na garagem com a porta aberta?",
        "churrasqueira dentro de casa",
        "Posso usar a churrasqueira a carvão dentro de casa?",
        "fogareiro na barraca",
        "Posso usar o fogareiro dentro da barraca para cozinhar?",
        "É seguro acender a churrasqueira na varanda fechada?",
        "Dá monóxido de carbono usar o fogareiro dentro da barraca?",
        "Acabou a luz. Posso deixar o gerador no porão com a janela aberta?",
        "Posso esquentar o carro na garagem com o portão fechado?",
        "Posso usar o forno a gás para aquecer a casa?",
        "O gerador a 3 metros da janela está bom?",
        "Podemos levar o aquecedor a querosene para o trailer durante a noite?",
        "Tudo bem usar carvão no quarto pra esquentar?",
        "Posso usar o aquecedor a gás dentro do carro?",
    ]
    private let es = [
        "¿Puedo usar un generador en el garaje?",
        "brasero dentro de la tienda",
        "¿Puedo usar un brasero de carbón dentro de casa?",
        "¿Es seguro usar una estufa de butano dentro de la carpa?",
        "¿Puedo encender la barbacoa en el garaje si dejo la puerta abierta?",
        "¿Puedo dejar el generador en el sótano toda la noche?",
        "¿Puedo calentar el coche en el garaje con la puerta cerrada?",
        "¿Puedo usar el horno de gas para calentar la casa?",
        "¿El monóxido de carbón del hornillo dentro de la tienda es peligroso?",
        "¿A qué distancia de la ventana tiene que estar el generador?",
        "¿Puedo usar una estufa de propano dentro del coche?",
    ]

    @Test func portugueseAndSpanishCoPlanningQuestionsFireInTheirLanguage() {
        for q in pt {
            let hit = LabTools.coHazard(q)
            #expect(hit.map { $0.text.contains(CoHazard.coHazardPt) && $0.text.contains(CoHazard.coHazardSourcesPt) } == true, "\(q)")
            #expect(hit?.tool == "safety-fact-co-hazard", "\(q)")
        }
        for q in es {
            let hit = LabTools.coHazard(q)
            #expect(hit.map { $0.text.contains(CoHazard.coHazardEs) && $0.text.contains(CoHazard.coHazardSourcesEs) } == true, "\(q)")
        }
    }

    @Test func symptomsAlarmsAndOtherQuestionsInPortugueseAndSpanishDont() {
        for q in [
            "estou com dor de cabeça perto do gerador",
            "Liguei o gerador na garagem e agora estou com tontura, o que faço?",
            "O alarme de monóxido está apitando no porão, o que eu faço?",
            "Usamos o fogareiro na barraca e meu filho está vomitando",
            "me duele la cabeza, el generador está en el garaje",
            "La alarma de CO está sonando en el sótano, ¿qué hago?",
            "qual a capital do Quênia",
            "Qual é a distância de Paris a Roma?",
            "¿Cuál es la capital de Kenia?",
            "Como funciona um gerador de senhas?",
            "¿Qué es un generador de contraseñas en la casa?",
            "Posso deixar o carro na garagem?",
            "Posso usar um aquecedor elétrico dentro da barraca?",
            "Como guardar o gerador na garagem para o inverno?",
            "Quanto custa um gerador?",
            "Onde compro carvão ativado dentro do shopping?",
            "¿Puedo comprar un generador en la tienda?",
            "O que é monóxido de carbono?",
        ] {
            #expect(LabTools.coHazard(q) == nil, "\(q)")
        }
    }

    @Test func startsWithNoOnlyWhenAskedWhetherToDoIt() {
        #expect(LabTools.coHazard("Posso usar aquecedor a gás dentro da barraca?")?.text.hasPrefix("Não. ") == true)
        #expect(LabTools.coHazard("gerador na garagem fechada")?.text.hasPrefix(CoHazard.coHazardPt) == true)
        #expect(LabTools.coHazard("É perigoso usar o gerador na garagem?")?.text.hasPrefix(CoHazard.coHazardPt) == true)
        #expect(LabTools.coHazard("¿Puedo usar un generador en el garaje?")?.text.hasPrefix("No. \(CoHazard.coHazardEs)") == true)
        #expect(LabTools.coHazard("brasero dentro de la tienda")?.text.hasPrefix(CoHazard.coHazardEs) == true)
        #expect(LabTools.coHazard("O gerador a 7 metros da janela está bom?").map { !$0.text.hasPrefix("Não") } ?? true)
    }

    @Test func theEmergencyLineFollowsTheLanguage() {
        #expect(LabTools.coHazard("Posso usar o gerador na garagem aqui no Brasil?")?.text.hasSuffix("Emergência — Brasil: polícia 190, ambulância (SAMU) 192, bombeiros 193.") == true)
        #expect(LabTools.coHazard("gerador na garagem fechada")?.text.hasSuffix("(192 SAMU, 193 Bombeiros no Brasil, 112 na Europa, 911 nos EUA).") == true)
        #expect(LabTools.coHazard("brasero dentro de la tienda")?.text.hasSuffix("(911 en EE. UU., 112 en Europa).") == true)
    }

    @Test func theEnglishAnswerIsUnchanged() {
        let q = "Can I run my portable generator in the attached garage if I keep the door open?"
        #expect(LabTools.coHazard(q)?.text == CoHazard.coHazardAnswer(q))
        #expect(LabTools.coHazard(q)?.text.hasPrefix("No. Carbon monoxide (CO) from a generator") == true)
        #expect(CoHazard.coHazardAnswer(q, language: "en") == CoHazard.coHazardAnswer(q))
    }
}
