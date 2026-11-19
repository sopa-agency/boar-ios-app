import BoarRouting
import Testing

@testable import BoarAnswer

/// android CoAcuteCardTest.kt (adam: "send co safety fix", Nov 14): a carbon monoxide alarm going off or symptoms got no
/// fixed text. The acute card answers first, alone, in EN, PT and ES, with the planning card's own advice.
struct CoAcuteCardTests {
    private func hit(_ q: String) -> LabTools.Hit? { LabTools.coHazard(q) }
    private func isCard(_ q: String) -> Bool { hit(q)?.tool == LabTools.coAcute }

    @Test func theAcutePhrasingsFireTheAcuteCardInTheQuestionsLanguage() {
        for q in [
            "My carbon monoxide alarm keeps going off and I have a headache and feel dizzy. What should I do?",
            "My CO alarm is beeping and I feel dizzy",
            "carbon monoxide alarm going off",
            "My carbon monoxide detector went off, what do I do?",
            "The CO detector reads 120 ppm",
            "I think I have carbon monoxide poisoning, I have a headache and feel sick",
        ] {
            let h = hit(q)
            #expect(h?.tool == LabTools.coAcute, "\(q)")
            #expect(h?.text.hasPrefix(CoHazard.coAcuteEn) == true, "\(q)")
        }
        for q in ["Meu alarme de monóxido de carbono está tocando e estou com dor de cabeça e tontura. O que faço?", "O detector de CO está apitando"] {
            #expect(hit(q).map { $0.tool == LabTools.coAcute && $0.text.hasPrefix(CoHazard.coAcutePt) } == true, "\(q)")
        }
        let es = "Mi alarma de monóxido de carbono está sonando y me duele la cabeza"
        #expect(hit(es).map { $0.tool == LabTools.coAcute && $0.text.hasPrefix(CoHazard.coAcuteEs) } == true)
    }

    @Test func theCardIsThePlanningCardsOwnAdviceThenTheEmergencyLineNothingNew() throws {
        #expect(CoHazard.coHazardEn.contains("get everyone out into fresh air right away, call emergency services, and don't go back inside until you're told it's safe."))
        #expect(CoHazard.coHazardPt.contains("leve todos para o ar livre imediatamente, ligue para o serviço de emergência e não volte para dentro até que digam que é seguro."))
        #expect(CoHazard.coHazardEs.contains("saca a todos al aire libre de inmediato, llama a los servicios de emergencia y no vuelvas a entrar hasta que te digan que es seguro."))
        let a = try #require(hit("carbon monoxide alarm going off")).text
        let tail = try #require(a.range(of: "\n\n")).upperBound
        #expect(a[tail...].contains("emergency"), "\(a)")
    }

    @Test func thePlanningControlStillGetsThePlanningCard() {
        #expect(hit("Can I run a generator in my garage?")?.tool == "safety-fact-co-hazard")
    }

    @Test func falsePositivesStayOut() {
        for q in ["My smoke alarm keeps going off", "CO2 levels in my office are high and I have a headache", "I'm moving to Colorado, I get headaches at altitude",
                  "I have a headache and feel dizzy", "Our CO-founder keeps beeping me", "The company CO is sick"] {
            #expect(hit(q) == nil, "\(q)")
        }
    }

    /// Android also reads ChatViewModel (never merged) and LabHooks (no bypass); here Labs.speaker maps the acute id to
    /// cohazard, whose answers have no "Ask BOAR instead".
    @Test func firstInOrder() {
        #expect(LabTools.slotRank("cohazard") == 0)
    }

    /// The bench's CO questions (android topics plugins.v1.json cohazard-acute, cohazard-acute-pt; health.v1.json
    /// health-co): the card and the text their rules expect. iOS has no topic files, so their queries and rules are here.
    @Test func theBenchsCoQuestionsGetTheCardAndTheTextTheirRulesExpect() {
        let bench: [(id: String, query: String, startsWith: String?, has: [String])] = [
            ("cohazard-acute", "My carbon monoxide alarm keeps going off and I feel dizzy. What do I do?",
             "Get everyone out into fresh air right away, call emergency services, and don't go back inside until you're told it's safe.", []),
            ("cohazard-acute-pt", "Meu alarme de monóxido de carbono está tocando e estou com tontura. O que faço?",
             "Leve todos para o ar livre imediatamente, ligue para o serviço de emergência e não volte para dentro até que digam que é seguro.", []),
            ("health-co", "My carbon monoxide alarm keeps going off and I have a headache and feel dizzy. What should I do?", nil, ["fresh air", "emergency"]),
        ]
        for q in bench {
            let h = hit(q.query)
            #expect(h?.tool == LabTools.coAcute, "\(q.id)")
            if let s = q.startsWith { #expect(h?.text.hasPrefix(s) == true, "\(q.id)") }
            for w in q.has { #expect(h?.text.range(of: w, options: .caseInsensitive) != nil, "\(q.id) \(w)") }
        }
    }

    /// t9's review table (Nov 14) with adam's decisions 2 and 3 (Nov 15): true = the acute card.
    private let review: [(String, Bool)] = [
        ("my carbon monoxide alarm is going off and I feel dizzy", true),
        ("My CO alarm keeps chirping every minute", false),
        ("My CO alarm chirps, how do I change the battery?", false),
        ("My CO detector reads 0 ppm, is that normal?", false),
        ("my CO detector says error", false),
        ("Is 50 ppm of carbon monoxide dangerous?", true),
        ("Can carbon monoxide cause headaches?", true),
        ("What are carbon monoxide poisoning symptoms like headache and nausea?", true),
        ("What are the symptoms of carbon monoxide poisoning?", false),
        ("does a carbon monoxide detector need to be on every floor?", false),
        ("my smoke alarm is beeping", false),
        ("CO2 levels are high and I feel dizzy", false),
        ("I ran the generator in the garage and now I have a headache", true),
    ]

    @Test func theReviewsThirteenQuestionsAsAdamDecided() {
        for (q, card) in review { #expect(isCard(q) == card, "\(q)") }
        // The ones without the card don't get the planning card either: the model answers them.
        for (q, card) in review where !card { #expect(hit(q) == nil, "\(q)") }
    }

    @Test func theSameDecisionsInPortugueseAndSpanish() {
        let cases: [(String, String?)] = [
            ("Meu alarme de monóxido de carbono está tocando e estou tonto", "pt"),
            ("O alarme de CO fica dando um bipe curto a cada minuto", nil),
            ("Meu detector de CO marca 0 ppm, é normal?", nil),
            ("O detector de monóxido mostra erro", nil),
            ("50 ppm de monóxido de carbono é perigoso?", "pt"),
            ("Monóxido de carbono causa dor de cabeça?", "pt"),
            ("Liguei o gerador na garagem e agora estou com dor de cabeça", "pt"),
            ("Acendi a churrasqueira dentro de casa e estou com tontura", "pt"),
            ("Mi alarma de monóxido de carbono está sonando y estoy mareado", "es"),
            ("Mi detector de CO marca 0 ppm, ¿es normal?", nil),
            ("¿50 ppm de monóxido de carbono es peligroso?", "es"),
            ("Encendí el generador en el garaje y ahora me duele la cabeza", "es"),
        ]
        for (q, lang) in cases {
            let h = hit(q)
            if let lang {
                #expect(h?.tool == LabTools.coAcute, "\(q)")
                let want = lang == "pt" ? CoHazard.coAcutePt : CoHazard.coAcuteEs
                #expect(h?.text.hasPrefix(want) == true, "\(q) | \(h?.text ?? "nil")")
            } else {
                #expect(h?.tool != LabTools.coAcute, "\(q)")
            }
        }
    }

    @Test func electricSolarAndBatteryGeneratorsStayOutWithASymptomToo() {
        for q in ["I used my solar generator in the tent and now I have a headache", "My battery generator is in the garage and I feel dizzy",
                  "Jackery generator indoors, I have a headache", "Meu gerador solar está na garagem e estou com dor de cabeça"] {
            #expect(!isCard(q), "\(q)")
        }
    }

    /// The validator's gate, part C: the acute card's false negatives.
    @Test func homeFuelAppliancesCountWithASymptomVentedOrNot() {
        for q in ["We all have headaches, the gas furnace was running all night",
                  "my head hurts and we have a gas water heater in the closet, the alarm keeps going off",
                  "headache and nausea, the whole house, the boiler was serviced yesterday",
                  "everyone in the house has a headache since the furnace was repaired",
                  "we lit the wood stove and now we feel dizzy", "headache after sitting by the fireplace all evening",
                  "the pellet stove is on and my kids are vomiting", "usamos a lareira e estamos com dor de cabeça e tontura"] {
            #expect(isCard(q), "\(q)")
        }
        // Electric ones stay out.
        for q in ["I have a headache, the electric heater is on", "my electric furnace is on and I have a headache"] {
            #expect(!isCard(q), "\(q)")
        }
    }

    @Test func anAlarmGoingOffAndASymptomFireWithNothingNamedNotWithSmoke() {
        for q in ["the alarm is going off and I feel dizzy", "alarm beeping, headache, nausea, whole family"] { #expect(isCard(q), "\(q)") }
        #expect(!isCard("the smoke alarm is going off and I feel dizzy"))
        #expect(!isCard("fire alarm ringing and I have a headache"))
    }

    @Test func pastTenseMoreAlarmVerbsTyposAndPortuguesePastForms() {
        for q in ["I felt sick after the generator ran", "I felt weak after the propane heater",
                  "I felt sick after the pressure washer ran in the basement",
                  "my CO alarm is ringing", "the carbon monoxide detector is buzzing", "co alarm just triggered and I'm dizzy",
                  "carbon monixide alarm going off", "carbon monoxid detector beeeping", "monoxide alarm going off", "c.o. alarm going off",
                  "o alarme de monóxido não para de apitar", "la alarma de monóxido no para de sonar",
                  "liguei o carro na garagem e estou com dor de cabeça"] {
            #expect(isCard(q), "\(q)")
        }
    }

    @Test func aSpanishReadingGetsTheSpanishCard() {
        for q in ["el detector de monóxido marca 60 ppm", "mi alarma de monóxido de carbono indica 40", "el monóxido de carbono está en 50 ppm en el sótano"] {
            #expect(hit(q)?.text.hasPrefix(CoHazard.coAcuteEs) == true, "\(q)")
        }
        #expect(hit("o detector de monóxido marca 60 ppm")?.text.hasPrefix(CoHazard.coAcutePt) == true)
    }

    @Test func adamsNoCardCasesStayNoCard() {
        for (q, card) in review { #expect(isCard(q) == card, "\(q)") }
        for q in ["my smoke alarm is beeping", "CO2 levels are high and I feel dizzy", "My CO alarm keeps chirping every minute",
                  "I used my solar generator in the tent and now I have a headache", "I have a headache and feel dizzy"] {
            #expect(!isCard(q), "\(q)")
        }
    }
}

/// android CoAcuteWordingTailTest.kt (validator Q-A1 and Q-A2): the acute CO card's remaining misses, and its over-triggers.
struct CoAcuteWordingTailTests {
    private func lang(_ q: String) -> String? { CoHazard.acuteLanguage(q) }

    @Test func ptAndEsPastTenseIFeltIllIsASymptom() {
        #expect(lang("a caldeira estava ligada e me senti mal") == "pt")
        #expect(lang("senti-me mal depois de ligar o aquecedor a gás") == "pt")
        #expect(lang("la estufa de leña estuvo encendida y me sentí mal") == "es")
    }

    @Test func spanishHornoDeGasIsADevice() {
        #expect(lang("tengo el horno de gas encendido y me duele la cabeza") == "es")
    }

    @Test func theWordingTail() {
        for q in [
            "the furnace was on all night and I'm woozy",
            "my head is spinning and the generator is in the garage",
            "the coal stove was burning all night and I have a headache",
            "we had a fire pit in the garage and now everyone is dizzy",
            "camp stove inside the cabin and I feel sick to my stomach",
            "my carbon monoxide alarm keeps going",
            "ALARM ALARM, we feel awful",
            "the gas heater was on and I have flu-like symptoms",
        ] { #expect(lang(q) == "en", "\(q)") }
        #expect(lang("el detector no deja de sonar y estoy mareado") == "es")
        #expect(lang("mi hijo está muy dormido y la estufa a gas está encendida") == "es")
    }

    @Test func noCardWhereAPersonWouldntGiveOne() {
        for q in [
            "my gas stove is great, I feel sick of cooking",
            "the boiler broke and I have a headache from the bill",
            "I felt sick after the boiler repair bill",
            "CO2 alarm beeping and I feel sick",
        ] { #expect(lang(q) == nil, "\(q)") }
        // Still a card: money named, but the headache is the generator's (CodeRabbit).
        for q in ["I cannot pay for heating, so I ran the generator inside and now I have a headache",
                  "the furnace repair was expensive, it ran all night and we all have headaches",
                  "we paid for propane and the space heater was on in the bedroom, now I'm dizzy"] {
            #expect(lang(q) == "en", "\(q)")
        }
        // Still a card: a bill named elsewhere doesn't hide a real exposure with carbon monoxide named.
        #expect(lang("carbon monoxide alarm going off and I have a headache, we just paid the boiler bill") == "en")
    }
}
