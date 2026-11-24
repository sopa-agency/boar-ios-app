import BoarRAG
import Foundation
import Testing

@testable import BoarAnswer

/// android CardRulesTest (t9 0207 item 2): the rules, conservative, every label and number copied from the answer. The
/// B-7 timing case is in LabTimingTests (run alone).
struct CardRulesTests {
    typealias Card = CardRules.Card
    typealias Shape = CardRules.Shape

    private func chart(_ cards: [Card]) -> (points: [CardRules.Point], unit: String, shapes: [Shape])? {
        for c in cards { if case .chart(let p, let u, let s) = c { return (p, u, s) } }
        return nil
    }
    private func steps(_ cards: [Card]) -> [String]? {
        for c in cards { if case .steps(let s) = c { return s } }
        return nil
    }
    private func facts(_ cards: [Card]) -> [CardFact]? {
        for c in cards { if case .facts(let f) = c { return f } }
        return nil
    }

    @Test func numberedStepsBecomeAChecklist() {
        let a = "To purify water:\n1. Collect clear water.\n2. Filter it through cloth [1].\n3. Boil it for one minute.\n4. Let it cool."
        let cards = CardRules.find("How do you purify water in the wild, step by step?", a)
        guard case .steps(let items) = cards.first else { Issue.record("\(cards)"); return }
        // The [1] mark goes; the words stay as written.
        #expect(items == ["Collect clear water.", "Filter it through cloth.", "Boil it for one minute.", "Let it cool."])
        #expect(cards[0].shapes == [.checklist])
    }

    @Test func bulletsAreStepsOnlyForAHowTo() {
        let a = "- Remove the wheel\n- Take out the tube\n- Patch the hole\n- Pump it up"
        guard case .steps = CardRules.find("How do I change a flat bicycle tyre?", a).first else { Issue.record("no steps"); return }
        #expect(steps(CardRules.find("Tell me about bicycles", a)) == nil)
    }

    @Test func anEnumerationOfThreeHeightsIsAChartCopiedAsWritten() {
        let a = "The three highest are Everest at 8,849 m, K2 at 8,611 m and Kangchenjunga at 8,586 m."
        let cards = CardRules.find("What are the three highest mountains, and how tall is each?", a)
        guard case .chart(let points, _, let shapes) = cards.first else { Issue.record("\(cards)"); return }
        #expect(points.map(\.label) == ["Everest", "K2", "Kangchenjunga"])
        #expect(points.map(\.written) == ["8,849 m", "8,611 m", "8,586 m"])
        #expect(points[0].value == 8849.0)
        #expect(shapes == [.bars, .table])
    }

    @Test func aListOfValuesInOneUnitIsAChartMixedUnitsAreNot() {
        let a = "- Water: 100 °C\n- Ethanol: 78 °C\n- Mercury: 357 °C"
        let cards = CardRules.find("What are the boiling points of water, ethanol and mercury?", a)
        guard case .chart(let points, _, _) = cards.first else { Issue.record("\(cards)"); return }
        #expect(points.map(\.label) == ["Water", "Ethanol", "Mercury"])
        let mixed = "- Moon: 384,400 km\n- Mars: 225 million km\n- Sun: 1 AU"
        #expect(chart(CardRules.find("How far?", mixed)) == nil)
    }

    @Test func aPieOnlyForPercentagesThatAddUpALineOnlyForYearsInOrder() {
        let pie = chart(CardRules.find("What is air made of?", "- Nitrogen: 78 %\n- Oxygen: 21 %\n- Argon: 1 %"))
        #expect(pie?.shapes.contains(.pie) == true)
        let noPie = chart(CardRules.find("Shares?", "- A: 30 %\n- B: 20 %\n- C: 10 %"))
        #expect(noPie != nil && noPie?.shapes.contains(.pie) == false)
        let line = chart(CardRules.find("Population over time?", "- 1990: 5 million\n- 2000: 6 million\n- 2010: 7 million"))
        #expect(line?.shapes.contains(.line) == true)
    }

    @Test func aMarkdownTable() {
        let a = "| Planet | Distance |\n|---|---|\n| Mars | 225 million km |\n| Venus | 41 million km |"
        let t = CardRules.find("Distances?", a).compactMap { c -> ([String], [[String]])? in
            if case .table(let h, let r) = c { return (h, r) } else { return nil }
        }.first
        #expect(t?.0 == ["Planet", "Distance"])
        #expect(t?.1.count == 2)
    }

    @Test func labelLinesAreFactsOrAComparisonWhenTheQuestionCompares() {
        let f = "Born: 7 November 1867\nField: Physics and chemistry\nKnown for: Radioactivity"
        guard case .facts = CardRules.find("Who was Marie Curie?", f).first else { Issue.record("no facts"); return }
        let cmp = "Solar: works by day; quiet, no moving parts\nWind: works day and night; needs steady wind"
        guard case .compare(let sides) = CardRules.find("Compare solar and wind power.", cmp).first else { Issue.record("no compare"); return }
        #expect(sides.map(\.name) == ["Solar", "Wind"])
    }

    @Test func paragraphsTheWayAnswersAreWrittenTodayHoldNoCard() {
        let a = "Marie Curie was a physicist and chemist who did pioneering research on radioactivity [1]. She was the first woman to win a Nobel Prize, "
            + "and the only person to win it in two sciences [2]. Born in Warsaw in 1867, she moved to Paris in 1891."
        #expect(CardRules.find("Who was Marie Curie?", a).isEmpty)
    }

    @Test func theItemsTheQuestionNamesOnePerSentenceFromTheF3sRealAnswers() {
        let boil = CardRules.find(
            "What are the boiling points of water, ethanol and mercury?",
            "Water boils at 100\u{202f}°C (212\u{202f}°F) at sea level [2]. Ethanol boils at approximately 78\u{202f}°C (173\u{202f}°F) [3]. Mercury boils at 357\u{202f}°C (675\u{202f}°F) [3]."
        )
        guard case .chart(let points, _, _) = boil.first else { Issue.record("\(boil)"); return }
        #expect(points.map(\.label) == ["Water", "Ethanol", "Mercury"])
        #expect(points.map(\.written) == ["100 °C", "78 °C", "357 °C"])
        let far = CardRules.find(
            "How far are the Moon, Mars and the Sun from Earth?",
            "The Moon is about 384,400 km from Earth. Mars varies from about 54.6 million to 401 million km away. The Sun is about 149.6 million km from Earth, on average. [1]"
        )
        // Mars gives two numbers (a range): not certain, so no card.
        #expect(far.isEmpty)
        // A question that names nothing: no pairing across sentences.
        #expect(CardRules.find("What are the three highest mountains, and how tall is each?", "Mount Everest is 8,850 m. K2 is 8,611 m. Kilimanjaro is 5,895 m.").isEmpty)
    }

    @Test func aListLabelMayHoldADigitK2TheNumberAfterItIsStillTheValue() {
        let cards = CardRules.find("What are the three highest mountains, and how tall is each?", "- Everest: 8,849 m\n- K2: 8,611 m\n- Kangchenjunga: 8,586 m")
        guard case .chart(let points, _, _) = cards.first else { Issue.record("\(cards)"); return }
        #expect(points.map(\.label) == ["Everest", "K2", "Kangchenjunga"])
        #expect(points.map(\.value) == [8849.0, 8611.0, 8586.0])
    }

    @Test func aNameNeverTakesAnotherItemsNumberB8() {
        let q = "What are the boiling points of water, ethanol and mercury?"
        // Ethanol's sentence names water after the number: it is ethanol's alone, and water's comes from its own sentence.
        let c = CardRules.find(q, "Ethanol boils at 78 °C, well below water. Water boils at 100 °C. Mercury boils at 357 °C.")
        guard case .chart(let points, _, _) = c.first else { Issue.record("\(c)"); return }
        #expect(points.map(\.label) == ["Water", "Ethanol", "Mercury"])
        #expect(points.map(\.value) == [100.0, 78.0, 357.0])
        // A sentence where the comparison comes first is no one's: no card rather than a wrong bar.
        #expect(chart(CardRules.find(q, "Compared with water, ethanol boils at 78 °C. Mercury boils at 357 °C.")) == nil)
    }

    @Test func negativesKeepTheirSignAndAChartWithOneIsATableB9() {
        let a = "The coldest inhabited places:\n- Oymyakon is -67 °C\n- Verkhoyansk is −68 °C\n- Yakutsk is -64 °C"
        let c = chart(CardRules.find("What are the coldest inhabited places?", a))
        #expect(c?.points.map(\.value) == [-67.0, -68.0, -64.0])
        #expect(c?.points.map(\.label) == ["Oymyakon", "Verkhoyansk", "Yakutsk"])
        #expect(c?.shapes == [.table])
        // A dash between name and number is still a separator.
        let peaks = chart(CardRules.find("Tallest peaks?", "- Everest - 8,849 m\n- K2 - 8,611 m\n- Kangchenjunga - 8,586 m"))
        #expect(peaks?.points.map(\.value) == [8849.0, 8611.0, 8586.0])
    }

    @Test func clockTimesAreNotFactsALabelWhoseValueHoldsATimeIsB10() {
        #expect(facts(CardRules.find("What does a typical day look like?", "- Breakfast 08:00\n- Lunch 12:30\n- Dinner 19:00")) == nil)
        let shop = facts(CardRules.find("When is the museum open?", "- Opening hours: 09:00 to 17:00\n- Closed: Mondays\n- Entry: free"))
        #expect(shop?.map(\.label) == ["Opening hours", "Closed", "Entry"])
    }

    @Test func aPortugueseAnswersDottedThousandsAreThousandsInTheChartB11() {
        let a = "As montanhas mais altas do mundo e do Brasil:\n- Everest: 8.849 m\n- K2: 8.611 m\n- Pico da Neblina: 2.995 m\n- Morro do Elefante: 300 m"
        #expect(chart(CardRules.find("Quais são as montanhas mais altas?", a))?.points.map(\.value) == [8849.0, 8611.0, 2995.0, 300.0])
        // English keeps reading "8.849" as a decimal when nothing says otherwise, and its "8,849" as thousands.
        let en = chart(CardRules.find("Tallest peaks?", "- Everest: 8,849 m\n- K2: 8,611 m\n- Kangchenjunga: 8,586 m"))
        #expect(en?.points.map(\.value) == [8849.0, 8611.0, 8586.0])
    }

    @Test func aRealLongAnswerUnderTheCapStillGetsItsCard() {
        // android B-7's last part (the timing parts are in LabTimingTests).
        let long = String(repeating: "x ", count: 4_000) + "\n- Everest: 8,849 m\n- K2: 8,611 m\n- Kangchenjunga: 8,586 m"
        #expect(long.utf16.count < CardRules.maxAnswer)
        #expect(chart(CardRules.find("Tallest peaks?", long)) != nil)
        #expect(CardRules.find("How tall?", String(repeating: "A", count: 40_000) + " is 5 m").isEmpty)
    }

    @Test func aShortPortugueseQuestionInAPortugueseAppReadsDottedThousandsAsThousandsRB2() {
        AnswerLanguage.$scoped.withValue(.init(app: "pt")) {
            let c = chart(CardRules.find("Montanhas mais altas?", "- Everest: 8.849 m\n- K2: 8.611 m\n- Morro: 300 m"))
            #expect(c?.points.map(\.value) == [8849.0, 8611.0, 300.0])
        }
    }

    @Test func aLabelEndingInANumberWithAValueThatIsntATimeStaysAFactRB5() {
        let levels = facts(CardRules.find("What does each level give?", "- Level 3: 10 points\n- Level 4: 20 points\n- Level 5: 30 points"))
        #expect(levels?.map(\.label) == ["Level 3", "Level 4", "Level 5"])
        // Times are still times.
        #expect(facts(CardRules.find("What does a typical day look like?", "- Breakfast 08:00\n- Lunch 12:30\n- Dinner 19:00 - 20:00")) == nil)
    }
}

/// android CiteMarksTest (validator Q-A4, t9 0115): no citation mark of any shape on a card, from the model or the rules.
struct CiteMarksTests {
    @Test func everyMarkShapeLeaves() {
        for m in ["[1]", "[1, 2]", "[1,2]", "[1-3]", "[1–3]", "[12]", "[1][2]", "[ 1 ]", "[S1]", "[^1]", "【1】", "【1, 2】", "[S1, S2]"] {
            #expect(CiteMarks.strip("Paris is the capital \(m).").replacingOccurrences(of: " .", with: ".") == "Paris is the capital.", "\(m)")
        }
    }

    @Test func codeInBackticksKeepsItsBracketsAndOtherBracketsStay() {
        #expect(CiteMarks.strip("Read `items[1]` first [2]") == "Read `items[1]` first")
        #expect(CiteMarks.strip("Mix [ratio a] well") == "Mix [ratio a] well")
        #expect(CiteMarks.strip("1990 [census]") == "1990 [census]")
    }

    @Test func aRulesChecklistDropsAListOfMarks() {
        let cards = CardRules.find(
            "How do I cool a burn?", "1. Run cool water over it for 20 minutes [1].\n2. Remove rings [2].\n3. Let it cool [1, 2].\n4. Cover it loosely [S1]."
        )
        let steps = cards.compactMap { c -> [String]? in if case .steps(let s) = c { return s } else { return nil } }.first
        #expect(steps != nil, "no steps card: \(cards)")
        #expect(steps?.contains { $0.contains("[") } == false, "\(steps ?? [])")
    }

}
