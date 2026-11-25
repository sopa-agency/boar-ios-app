import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// android AnswerCardTest (t9 0207 items 3 and 4): the card shown under an answer, its switch, its place in the meta, and
/// its Markdown. The PressDoc part of R-E3 waits for Press's card (BOAR-55).
struct AnswerCardTests {
    typealias Shape = CardRules.Shape
    private let peaksQ = "What are the three highest mountains, and how tall is each?"
    private let peaks = "The three highest are Everest at 8,849 m, K2 at 8,611 m and Kangchenjunga at 8,586 m."
    private let breadQ = "How do I make a simple no-knead bread?"
    private let bread = "You need:\n- Flour: 500 g\n- Water: 350 g\n- Salt: 10 g\n- Yeast: 3 g\n\n1. Mix everything in a bowl.\n2. Cover it and let it rest for 12 hours.\n3. Shape it into a ball.\n4. Bake it 45 minutes at 230 °C."

    @Test func theSwitchHoldsEveryShapeOfEveryCardFoundBestFirst() {
        #expect(AnswerCard.choices(CardRules.find(peaksQ, peaks)) == [AnswerCard.Choice(0, .bars), AnswerCard.Choice(0, .table)])
        let choices = AnswerCard.choices(CardRules.find(breadQ, bread))
        // The how-to's checklist first, then the amounts as bars and a table (no pie: grams are not parts of 100 %).
        #expect(choices.first?.shape == .checklist)
        #expect(choices.contains { $0.shape == .bars } && !choices.contains { $0.shape == .pie })
    }

    @Test func aRuleCardCopiesTheAnswerWithATitleFromWhatTheChatShows() throws {
        let chart = try #require(CardRules.find(peaksQ, peaks).first)
        let card = AnswerCard.of(chart, .table, title: AnswerCard.titleFor(chart, question: peaksQ, sources: ["List of highest mountains on Earth"]))
        #expect(card.shape == .table)
        #expect(card.title == "List of highest mountains on Earth")
        #expect(!card.byModel)
        let t = try #require(AnswerCard.asTable(card))
        #expect(t.header == ["", "m"])
        #expect(t.rows == [["Everest", "8,849 m"], ["K2", "8,611 m"], ["Kangchenjunga", "8,586 m"]])
        // No source: the question, short; a comparison names its sides.
        #expect(AnswerCard.titleFor(chart, question: peaksQ, sources: []) == "What are the three highest mountains, and how tall is each")
        let cmp = CardRules.Card.compare([CardSide("Solar", ["by day"]), CardSide("Wind", ["day and night"])])
        #expect(AnswerCard.titleFor(cmp, question: "Compare solar and wind power.", sources: ["Solar power"]) == "Solar · Wind")
        // A shape the card doesn't have falls back to its first.
        #expect(AnswerCard.of(chart, .pie, title: "t").shape == .bars)
    }

    @Test func whatTheSheetsLineCounts() throws {
        let a = AnswerCard.found(try #require(CardRules.find(peaksQ, peaks).first))
        #expect(a.0 == .chart && a.1 == 3)
        let b = AnswerCard.found(try #require(CardRules.find(breadQ, bread).first))
        #expect(b.0 == .steps && b.1 == 4)
    }

    @Test func everyKindReadsBackAsWrittenTicksWithIt() {
        let cards = [
            AnswerCard(.bars, "Peaks", .series(unit: "m", points: [CardRules.Point("Everest", "8,849 m", 8849), CardRules.Point("K2", "8,611 m", 8611)])),
            AnswerCard(.table, "T", .table(header: ["A", "B"], rows: [["1", "2"]])),
            AnswerCard(.checklist, "S", .steps(["one", "two", "three"]), ticks: [0, 2]),
            AnswerCard(.facts, "F", .facts([CardFact("Born", "1867")])),
            AnswerCard(.compare, "C", .compare([CardSide("Solar", ["by day"]), CardSide("Wind", ["at night"])])),
            AnswerCard(.pie, "M", .series(unit: "%", points: [CardRules.Point("N", "78 %", 78)]), byModel: true, leftOut: ["Argon"]),
            AnswerCard(.bars, "Decimals", .series(unit: "m", points: [CardRules.Point("A", "3.25 m", 3.25), CardRules.Point("B", "-0.5 m", -0.5)])),
        ]
        for c in cards {
            #expect(AnswerCard.fromJson(AnswerCard.toJson(c, withTicks: true)) == c)
            // Through the meta's text too, as the chat store keeps it.
            #expect(AnswerCard.fromJson(JSONValue(jsonString: AnswerCard.toJson(c, withTicks: true).jsonString)) == c)
        }
        // In the meta the ticks live beside the card, not in it.
        #expect(AnswerCard.toJson(cards[2])["ticks"] == nil)
        #expect(AnswerCard.fromJson(JSONValue(jsonString: #"{"shape":"HEXAGON","kind":"steps","steps":["a"]}"#)) == nil)
        #expect(AnswerCard.fromJson(JSONValue(jsonString: #"{"shape":"BARS","kind":"poster"}"#)) == nil)
    }

    @Test func theCardAndItsTicksJoinTheAnswersMetaTheRestOfItKept() throws {
        let meta = #"{"sources":[{"title":"Everest","body":"…"}],"receipt":{"model":"Qwen3 4B"}}"#
        let card = AnswerCard(.checklist, "S", .steps(["a", "b", "c"]))
        let with = try #require(AnswerCard.withCard(meta, card))
        let ticked = try #require(AnswerCard.withTicks(with, [1]))
        let o = try #require(JSONValue(jsonString: ticked)?.objectValue)
        #expect(o["sources"] != nil && o["receipt"] != nil && o["card"] != nil && o["cardTicks"] != nil)
        var withTicks = card
        withTicks.ticks = [1]
        #expect(AnswerCard.fromMeta(ticked) == withTicks)
        #expect(AnswerCard.ticksFromMeta(ticked) == [1])
        // ✕ takes the card and its ticks; the receipt stays.
        let removedMeta = try #require(AnswerCard.withCard(ticked, nil))
        let removed = try #require(JSONValue(jsonString: removedMeta)?.objectValue)
        #expect(removed["receipt"] != nil && removed["card"] == nil && removed["cardTicks"] == nil)
        // No meta yet starts one; a meta that can't be read is never written over.
        #expect(AnswerCard.fromMeta(AnswerCard.withCard(nil, card)) == card)
        #expect(AnswerCard.withCard("not json", card) == nil)
        #expect(AnswerCard.withTicks("[1,2]", [1]) == nil)
        #expect(AnswerCard.fromMeta(meta) == nil)
    }

    @Test func theModelsCardIsMarkedAsMadeByTheModelAShareAsAPie() {
        let v = Visual.series(.init("Air", .share, "%", [VisualItem("Nitrogen", 78), VisualItem("Oxygen", 21), VisualItem("Argon", 1)]))
        let c = AnswerCard.ofVisual(v, leftOut: ["CO2"], fallbackTitle: "fallback")
        #expect(c.shape == .pie)
        #expect(c.byModel)
        #expect(c.leftOut == ["CO2"])
        guard case .series(_, let points) = c.body else { Issue.record("not a series"); return }
        #expect(points.map(\.written) == ["78 %", "21 %", "1 %"])
        #expect(AnswerCard.percents(points) == [78, 21, 1])
        #expect(AnswerCard.ofVisual(.steps(.init("", ["a", "b"])), leftOut: [], fallbackTitle: "fallback").title == "fallback")
    }

    @Test func inMarkdownATableForASeriesNumberedStepsLabelLinesAListUnderEachName() throws {
        let chart = AnswerCard.of(try #require(CardRules.find(peaksQ, peaks).first), .bars, title: "Peaks")
        #expect(AnswerCard.markdown(chart, nameLabel: "Name")
            == "**Peaks**\n\n| Name | m |\n| --- | --- |\n| Everest | 8,849 m |\n| K2 | 8,611 m |\n| Kangchenjunga | 8,586 m |")
        #expect(AnswerCard.markdown(AnswerCard(.checklist, "S", .steps(["one", "two"]), ticks: [0])) == "**S**\n\n1. one\n2. two")
        #expect(AnswerCard.markdown(AnswerCard(.facts, "", .facts([CardFact("Born", "1867"), CardFact("Field", "Physics")]))) == "- Born: 1867\n- Field: Physics")
        #expect(AnswerCard.markdown(AnswerCard(.compare, "", .compare([CardSide("Solar", ["by day"]), CardSide("Wind", ["at night"])])))
            == "**Solar**\n- by day\n**Wind**\n- at night")
        // A cell's | can't break the table.
        #expect(AnswerCard.markdown(AnswerCard(.table, "", .table(header: ["a|b"], rows: [["x"]]))).hasPrefix("| a\\|b |"))
    }

    @Test func aModelsCardNegativesAsATableNoAnswerMarksRE1RE2() {
        let cold = Visual.series(.init("Coldest", .bars, "°C", [VisualItem("Oymyakon [1]", -67), VisualItem("Yakutsk", 5)]))
        let c = AnswerCard.ofVisual(cold, leftOut: [], fallbackTitle: "t")
        #expect(c.shape == .table)
        if case .series(_, let points) = c.body { #expect(points.map(\.label) == ["Oymyakon", "Yakutsk"]) } else { Issue.record("not a series") }
        let steps = AnswerCard.ofVisual(.steps(.init("Boil [2]", ["Boil the water [1]", "Let it cool [1, 2]"])), leftOut: [], fallbackTitle: "t")
        #expect(steps.body == .steps(["Boil the water", "Let it cool"]))
        #expect(steps.title == "Boil")
    }

    /// android CanvasLab `titleSources` over PressReceipt.shareable (validator R-A1): a rule card's title comes from a
    /// pack's source, never from a user's own file, whose title is its file name.
    @Test func aRuleCardsTitleComesOnlyFromAPacksSource() {
        let sources: [(title: String, source: String?)] = [
            ("imposto-2025.pdf", "imposto-2025.pdf"), ("Notes", nil),
            ("Mount Everest", "Wikipedia — https://en.wikipedia.org/wiki/Mount_Everest"), ("K2", "Wikipedia"), ("Ask", "BOAR FAQ"),
        ]
        #expect(AnswerCard.titleSources(sources) == ["Mount Everest", "K2", "Ask"])
        #expect(!AnswerCard.shareable("  "))
        #expect(AnswerCard.titleFor(.steps(["a", "b"]), question: "How do I boil water?", sources: AnswerCard.titleSources(sources)) == "Mount Everest")
    }
}

/// android AnswerCardPtTest (coder's F3 check, 15 Nov): a model's card under a Portuguese answer dropped Brasil, whose
/// area the answer gives twice, and wrote the areas English-style (3,287,263) under an answer that wrote 3.287.263.
struct AnswerCardPtTests {
    // The 1.7B's answer on the F3, as shown (its facts are wrong; the card is checked against it, not against the world).
    private let answer = "O Brasil é o país com maior área no mundo [2], com uma área total de aproximadamente 8.515.814 km². "
        + "A Índia é o segundo maior país em área [2], com uma área de aproximadamente 3.287.263 km². "
        + "A China é o terceiro maior país em área [2], com uma área de aproximadamente 9.599.185 km². "
        + "O Brasil, por sua vez, é o maior país do hemisfério sul, com uma área de 8.515.814 km², enquanto a China é o maior país do hemisfério norte."
    private let raw = #"{"type":"table","title":"Maiores paises do mundo em area","columns":["Pais","Area (km²)"],"rows":[["Brasil","8,515,814"],["Índia","3,287,263"],["China","9,599,185"]]}"#

    @Test func aNameInTheNextSentenceDoesntTakeThisSentencesNumber() {
        guard case .ok(.table(let t), let leftOut) = Visual.parse(raw, answer: answer) else { Issue.record("\(Visual.parse(raw, answer: answer))"); return }
        #expect(leftOut.isEmpty, "\(leftOut)")
        #expect(t.rows.map { $0[0] } == ["Brasil", "Índia", "China"])
    }

    @Test func theCardWritesEachNumberAsTheAnswerDoes() {
        guard case .ok(let v, let leftOut) = Visual.parse(raw, answer: answer) else { Issue.record("refused"); return }
        let card = AnswerCard.ofVisual(v, leftOut: leftOut, fallbackTitle: "t", answer: answer)
        guard case .table(_, let rows) = card.body else { Issue.record("not a table"); return }
        #expect(rows.map { $0[1] } == ["8.515.814", "3.287.263", "9.599.185"])
        // An English answer keeps its own spelling; a number the answer doesn't hold stays as the model wrote it.
        #expect(VisualCheck.asWritten("8,849 m", "Everest is 8,849 m tall.") == "8,849 m")
        #expect(VisualCheck.asWritten("12,5 %", "Nothing here.") == "12,5 %")
    }

    private func refusedOrPruned(_ p: Visual.Parsed) -> Bool {
        if case .ok(_, let leftOut) = p { return !leftOut.isEmpty }
        return true
    }

    @Test func theSwapThePairingRuleWasMadeForIsStillRefused() {
        let en = "Paris has 2.1 million people. Lyon has 0.5 million people."
        let swapped = #"{"type":"bars","title":"Pop","unit":"million","items":[{"label":"Paris","value":0.5},{"label":"Lyon","value":2.1}]}"#
        #expect(refusedOrPruned(Visual.parse(swapped, answer: en)))
    }

    @Test func aSwappedCardIsRefusedInEveryLayoutSentencesApartTooRB1() {
        let swapped = #"{"type":"bars","title":"Pop","unit":"million","items":[{"label":"Paris","value":0.5},{"label":"Lyon","value":2.1}]}"#
        let right = #"{"type":"bars","title":"Pop","unit":"million","items":[{"label":"Paris","value":2.1},{"label":"Lyon","value":0.5}]}"#
        for text in [
            "Paris has 2.1 million people. Lyon has 0.5 million people.",
            "Paris. It has 2.1 million people. Lyon. It has 0.5 million people.",
            "Paris is a city. It has 2.1 million people. Lyon is a city. It has 0.5 million people.",
            "## Paris\nIt has 2.1 million people.\n## Lyon\nIt has 0.5 million people.",
        ] {
            let bad = Visual.parse(swapped, answer: text)
            #expect(refusedOrPruned(bad), "\(text) -> \(bad)")
            let ok = Visual.parse(right, answer: text)
            if case .ok(_, let leftOut) = ok { #expect(leftOut.isEmpty, "\(text)") } else { Issue.record("\(text) -> \(ok)") }
        }
    }
}
