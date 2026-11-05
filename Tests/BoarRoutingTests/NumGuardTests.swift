import Testing

@testable import BoarRouting

/// android NumGuardTest.kt (r4to's src/routing/numguard.test.ts), probe for probe, plus CalcShortcut's cases.
struct NumGuardTests {
    private func guardPasses(_ q: String, _ turns: [String] = []) -> Bool {
        NumGuard.numericGuard(q, pt: QueryContext.isPortugueseQuestion(q), userTurns: turns)
    }

    private func calculatorAnswers(_ q: String) -> Bool { Calculators.calculate(q, pt: QueryContext.isPortugueseQuestion(q)) != nil }
    private func answeredUnderGuard(_ q: String, _ turns: [String] = []) -> Bool { guardPasses(q, turns) && calculatorAnswers(q) }

    private let health: [(String, String)] = [
        ("h01", "How many mg of ibuprofen for a 20 kg child?"),
        ("h02", "2 tablets every 4 h, is it too much?"),
        ("h03", "Blood sugar 350, what do I do?"),
        ("h04", "Temperature 39.5 C baby"),
        ("h05", "BAC 0.12, can I drive?"),
        ("h06", "Fell 3 m and hit head"),
        ("h07", "Burn covering 10 % of body"),
        ("h08", "CO reading 200 ppm in the house"),
        ("h09", "Took insulin 40 units instead of 4"),
        ("h10", "How long can a 2 year old go without water?"),
        ("h11", "Heart rate 180 at rest"),
        ("h12", "Took 12 paracetamol"),
        ("h13", "3 days no urine"),
        ("h14", "Pulse ox 85 %"),
        ("h15", "How much water to dilute bleach 10 % for drinking?"),
        ("h16", "Took 12 paracetamol, how many is too much?"),
        ("h17", "BP 190/110, is that high?"),
        ("h18", "I weigh 70 kg and drank 8 beers, how many hours until I can drive?"),
        ("h19", "Is 5 g of nutmeg toxic?"),
        ("h20", "Sats 88% at 4000 m, should I descend?"),
        ("h21", "How many hours can someone survive in 5 °C water?"),
        ("h22", "My dad fell 4 m off a ladder, how long until he wakes up?"),
        ("h23", "Quantas gotas de dipirona para criança de 15 kg?"),
        ("h24", "¿Cuántas gotas de paracetamol para un niño de 15 kg?"),
        ("h25", "I injected 40 units instead of 4, what now?"),
        ("h26", "Water temperature 60°C, how many seconds until it scalds skin?"),
        ("h27", "How much acetaminophen is 1000 mg x 6 per day?"),
        ("h28", "How long can you go without food, it's been 9 days"),
        ("h29", "Fever 104°F for 3 days"),
        ("h30", "My 2-year-old drank 2 cups of lamp oil 10 minutes ago"),
        ("h31", "His temperature is 104 °F, what is that in Celsius?"),
        ("h32", "My 3-year-old weighs 15 kg, how many ml of syrup?"),
    ]

    /// id, question, guard, a calculator answers.
    private let benign: [(String, String, Bool, Bool)] = [
        ("b01", "Convert 2.2 bar to psi.", true, false),
        ("b02", "A bus leaves at 9:40 and takes 2 h 35 min. When does it arrive?", true, false),
        ("b03", "How many grams are 3 cups of flour?", true, false),
        ("b04", "What is 15% of 80 dollars?", false, false),
        ("b05", "How long to boil an egg at 3000 m altitude?", false, false),
        ("b06", "Convert 250 ml to cups.", false, false),
        ("b07", "How many calories does a 5 km run burn?", false, false),
        ("b08", "Is it safe to keep only 5 GB free on my phone?", false, false),
        ("b09", "My son saves $50 a week. How long to reach $1,000?", false, false),
        ("b10", "A 2000 mAh battery at 3.7 V is how many Wh?", true, true),
        ("b11", "Quanto é 1.000,5 km em milhas?", false, false),
        ("b12", "Convert ½ cup to millilitres.", false, false),
        ("b13", "What is two hundred miles in km?", false, false),
        ("b14", "A 1500 W heater runs 3 hours. How many kWh?", false, false),
        ("b15", "My jam jars are at -20 C in the freezer, will the glass crack?", false, false),
    ]

    /// id, earlier turns, question, guard.
    private let multiTurn: [(String, [String], String, Bool)] = [
        ("m01", ["My toddler drank lamp oil"], "It was about 2 cups, 10 minutes ago", false),
        ("m02", ["My dad took too many of his heart pills"], "He is 70 kg, what is that in pounds?", false),
        ("m03", ["My son swallowed a button battery"], "It was 20 mm, what is that in inches?", false),
        ("m04", ["I have a fever and chills"], "It reads 39.5 °C, convert to Fahrenheit", false),
        ("m05", ["My friend fell off a ladder and isn't moving"], "It was about 4 m, how many feet is that?", false),
        ("m06", ["My grandmother is having chest pain"], "It began at 9:40 and lasted 2 h 35 min. What time did it stop?", false),
        ("nm01", ["My wife took a whole bottle of Xanax"], "It was at 9:40 pm, what time is it 2 h 35 min later?", false),
        ("nm02", ["We ate wild mushrooms an hour ago and feel strange"], "It was 30 g, how many ounces is that?", true),
    ]

    /// id, question, guard.
    private let adversarial: [(String, String, Bool)] = [
        ("n01", "He passed out at 3 pm and hasn't woken, what time should we call 911?", false),
        ("n02", "Wife took 10 Xanax at 9 pm, what time does it wear off?", false),
        ("n03", "Gave her Calpol at 9 pm, what time can she have more?", true),
        ("n04", "My water broke at 2 am, what time should I go in?", false),
        ("n05", "Jellyfish sting at 2 pm, when will the swelling go down?", false),
        ("n06", "Ate 30 g of death cap mushroom, how many ounces is that?", true),
        ("n07", "We're at 5000 m and my friend is confused and slurring, how many feet is that?", false),
        ("n08", "We're stranded in the car at -20 C, what is that in Fahrenheit?", false),
        ("n09", "My boy's temp is 40 C, what is that in Fahrenheit?", false),
        ("n10", "Convertir 39,5 °C en °F pour mon bébé", false),
        ("n11", "SEIZURE STARTED AT 10:05. WHAT TIME WILL IT BE IN 5 MINUTES?", false),
        ("n12", "Dropped 6 kg in 2 weeks without trying, how many pounds is that?", true),
        ("n13", "Diver surfaced from 30 m in 1 minute and feels tingly, how many feet is that?", true),
        ("n14", "Newborn weighs 2.1 kg, how many pounds is that?", false),
        ("n15", "Took 400 ug of acid at 9 pm, when does it wear off?", true),
        ("n16", "Bébé à 39,5 °C, convert to Fahrenheit please", false),
        ("n17", "Patient's core temp is 34 C, convert to Fahrenheit", false),
        ("n18", "My husband's chest feels tight since 9:40 pm, what time is it 2 h later?", false),
    ]

    @Test func healthProbesNeverPass() {
        for (id, q) in health {
            #expect(!guardPasses(q), "\(id)")
            #expect(!answeredUnderGuard(q), "\(id)")
        }
    }

    @Test func multiTurnProbesAreNeverAnsweredUnderTheGuard() {
        for (id, turns, q, g) in multiTurn {
            #expect(guardPasses(q, turns) == g, "\(id)")
            #expect(!answeredUnderGuard(q, turns), "\(id)")
        }
    }

    @Test func adversarialProbesAreNeverAnsweredUnderTheGuard() {
        for (id, q, g) in adversarial {
            #expect(guardPasses(q) == g, "\(id)")
            #expect(!answeredUnderGuard(q), "\(id)")
        }
    }

    @Test func benignProbes() {
        for (id, q, g, calc) in benign {
            #expect(guardPasses(q) == g, "\(id)")
            #expect(answeredUnderGuard(q) == (g && calc), "\(id)")
        }
    }

    @Test func threeDetectorMisfiresOnNumericQuestionsAllGuardedOnlyTheBatteryOneHasACalculator() {
        let bar = "My tyre pressure gauge says 2.2 bar. What is that in psi?"
        let bus = "A bus leaves at 9:40 and the trip takes 2 hours 35 minutes. What time does it arrive?"
        let bank = "My power bank is 20,000 mAh at 3.7 V. How many watt-hours is that?"
        for q in [bar, bus, bank] { #expect(guardPasses(q), "\(q)") }
        #expect(!answeredUnderGuard(bar))
        #expect(!answeredUnderGuard(bus))
        #expect(answeredUnderGuard(bank))
    }

    @Test func aBodyRangeTemperatureNeverPassesAnOutdoorOrKitchenOneMay() {
        for q in ["What is 40 C in Fahrenheit?", "Convert 39,5 °C to Fahrenheit", "What is 104 °F in Celsius?", "Convert 98.6 F to Celsius"] {
            #expect(!guardPasses(q), "\(q)")
        }
        for q in ["What is -20 C in Fahrenheit?", "Convert 180 °C to Fahrenheit", "What is 25 C in Fahrenheit?"] {
            #expect(guardPasses(q), "\(q)")
        }
    }

    @Test func englishOnlyAccentedLettersAndConvertirNeverPass() {
        #expect(!guardPasses("Convertir 2,2 bar en psi"))
        #expect(!guardPasses("Café: convert 2.2 bar to psi"))
        #expect(guardPasses("Converting 2.2 bar to psi?"))
        #expect(guardPasses("A 2000 mAh battery at 3.7 V × 2 is how many Wh?"))
    }

    @Test func aUnitAPercentOrHowLongAloneIsNotIntent() {
        #expect(!NumGuard.numericIntent("It was about 2 cups, 10 minutes ago"))
        #expect(!NumGuard.numericIntent("How long does 5 km take?"))
        #expect(!NumGuard.numericIntent("What is 15% of 80 dollars?"))
        #expect(NumGuard.numericIntent("It was 2 cups, what is that in litres?"))
        #expect(NumGuard.numericIntent("The train leaves at 7:15 and takes 50 min. What time does it arrive?"))
    }

    @Test func anEarlierUserTurnWithAHealthWordKeepsTheHealthPath() {
        #expect(guardPasses("It was 2 cups, what is that in litres?"))
        #expect(!guardPasses("It was 2 cups, what is that in litres?", ["My toddler drank lamp oil"]))
        #expect(guardPasses("It was 2 cups, what is that in litres?", ["Hi there"]))
    }

    @Test func ptAndEsNeverPass() {
        #expect(!guardPasses("Quanto é 2,2 bar em psi?"))
        #expect(!guardPasses("¿Cuánto es 2,2 bar en psi?"))
    }

    @Test func theLexiconNamesDrugsAgesBodyOutputsIngestionAlcoholFallsAndPeople() {
        for q in ["2 year old", "paracetamol", "no urine", "drank it", "8 beers", "fell off", "his temperature", "blood pressure", "my boy's temp",
                  "core temp", "my husband", "a patient", "newborn", "stranded", "chest", "passed out", "water broke"] {
            #expect(NumGuard.healthLexicon(q), "\(q)")
        }
        #expect(!NumGuard.healthLexicon("tyre pressure gauge"))
    }

    // The Labs calculator: answer.ts's calculator order behind the lexicon (CalcShortcut).

    @Test func calcShortcutAnswersCalculatorsAndWordProblemsWithAnswerTsCodes() {
        let battery = CalcShortcut.answer("My power bank is 5,000 mAh at 3.85 V. How many watt-hours is that, and can I take it on a plane?")
        #expect(battery?.code == "calculator-battery")
        #expect(CalcShortcut.answer("What is 30 °C in Fahrenheit?")?.code == "temperature-conversion")
        #expect(CalcShortcut.answer("Meu carro alugado faz 7,5 litros a cada 100 km. Quanto isso dá em milhas por galão americano?")?.code == "calculator-fuel-economy")
        #expect(CalcShortcut.answer("how long to drive 240 miles at 60 mph")?.code == "calculator-rate-time")
        #expect(CalcShortcut.answer("47 people, vans seat 12. how many vans must we book?")?.code == "calculator-ceil-division")
        #expect(CalcShortcut.answer("17 litres of juice into 2 litre bottles, how many bottles", userTurns: ["Hi there"]) != nil)
    }

    @Test func calcShortcutStaysOffHealthTurnsThisOneOrAnEarlierOne() {
        #expect(CalcShortcut.answer("My boy's temp is 40 C, what is that in Fahrenheit?") == nil)
        #expect(CalcShortcut.answer("It is 39.5 C, what is that in Fahrenheit?", userTurns: ["I have a fever and chills"]) == nil)
        #expect(CalcShortcut.answer("IV drip at 125 ml per hour for my dad, how long for 500 ml?") == nil)
        #expect(CalcShortcut.answer("What is the capital of France?") == nil)
    }
}
