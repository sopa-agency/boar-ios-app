import Foundation
import Testing

@testable import BoarAnswer

/// android VisualTest: the merged visual, its contract, the grounding of every number and label, and what the app
/// computes. CardSpec isn't ported (unused in v2.0.0), so the saved-card case checks Visual alone.
struct VisualTests {
    private let peaks = "Mount Everest is 8,849 m high, K2 is 8,611 m and Kangchenjunga 8,586 m. Everest was first climbed on 29 May 1953."
    private let pt = "A população do Brasil é de 203,1 milhões; a Rússia tem 146.4 milhões e uma área de 17.098.246 km²."

    private func ok(_ raw: String, _ answer: String, _ user: String = "", sourceLocation: SourceLocation = #_sourceLocation) -> Visual? {
        let p = Visual.parse(raw, answer: answer, userText: user)
        if case .ok(let v, _) = p { return v }
        Issue.record("rejected: \(p)", sourceLocation: sourceLocation)
        return nil
    }
    private func isOk(_ raw: String, _ answer: String) -> Bool {
        if case .ok = Visual.parse(raw, answer: answer) { return true }
        return false
    }
    private func okLeftOut(_ raw: String, _ answer: String) -> (Visual, [String])? {
        if case .ok(let v, let l) = Visual.parse(raw, answer: answer) { return (v, l) }
        return nil
    }
    private func reason(_ raw: String, _ answer: String, _ user: String = "") -> Visual.Reason? {
        if case .rejected(let r, _) = Visual.parse(raw, answer: answer, userText: user) { return r }
        return nil
    }
    private func series(_ v: Visual?) -> Visual.Series? { if case .series(let s)? = v { return s } else { return nil } }
    private func table(_ v: Visual?) -> Visual.Table? { if case .table(let t)? = v { return t } else { return nil } }
    private func facts(_ title: String, _ pairs: [(String, String)]) -> Visual { .facts(.init(title, pairs.map { CardFact($0.0, $0.1) })) }

    // MARK: The contract

    @Test func barsLineAndShareReadAsOneSeriesPieAsShare() {
        let items = #"[{"label":"Everest","value":8849},{"label":"K2","value":8611},{"label":"Kangchenjunga","value":8586}]"#
        for (type, kind) in [("bars", Visual.SeriesKind.bars), ("line", .line), ("share", .share), ("pie", .share)] {
            let v = series(ok(#"{"type":""# + type + #"","title":"Highest peaks","unit":"m","items":"# + items + "}", peaks))
            #expect(v?.kind == kind, "\(type)")
            #expect(v?.items.map(\.value) == [8849.0, 8611.0, 8586.0])
            #expect(v?.unit == "m")
        }
    }

    @Test func aCardSavedBeforeReadsTheSame() {
        let old = [
            #"{"type":"table","title":"Peaks","columns":["Peak","Height"],"rows":[["Everest","8,849 m"],["K2","8,611 m"]]}"#,
            #"{"type":"bars","title":"Peaks","unit":"m","items":[{"label":"Everest","value":8849},{"label":"K2","value":"8,611"}]}"#,
            #"{"type":"steps","title":"Climb","steps":["Everest was climbed","in May 1953"]}"#,
            #"{"type":"compare","title":"Two peaks","items":[{"name":"Everest","points":["8,849 m high"]},{"name":"K2","points":["8,611 m"]}]}"#,
            #"{"type":"facts","title":"Everest","facts":[{"label":"Height","value":"8,849 m"},{"label":"First climbed","value":"29 May 1953"}]}"#,
        ]
        for raw in old { #expect(isOk(raw, peaks), "\(raw)") }
    }

    @Test func theReplyMayComeInAFenceAfterReasoningOrWithABraceInAString() {
        let raw = "<think>{\"type\":\"bars\"} maybe</think>Here it is:\n```json\n{\"type\":\"facts\",\"title\":\"Everest {tallest}\",\"facts\":[{\"label\":\"Height\",\"value\":\"8,849 m\"}]}\n```"
        #expect(ok(raw, peaks)?.title == "Everest {tallest}")
    }

    @Test func noneReservedKindsUnknownTypesBrokenJSONAndEmptyDataAreRefused() {
        #expect(reason(#"{"type":"none"}"#, peaks) == .nothing)
        for k in ["timeline", "slider", "quiz", "converter"] { #expect(reason(#"{"type":""# + k + #"","items":[]}"#, peaks) == .reserved, "\(k)") }
        #expect(reason(#"{"type":"map"}"#, peaks) == .unknownType)
        #expect(reason("I think a table would help.", peaks) == .noJson)
        #expect(reason(#"{"type":"bars","items":["#, peaks) == .noJson)
        #expect(reason(#"{"type":"bars","items":[{"label":"Everest","value":8849}]}"#, peaks) == .empty)
        #expect(reason(#"{"type":"steps","steps":["only one"]}"#, peaks) == .empty)
    }

    @Test func aShareNeedsPartsThatCanMakeAWhole() {
        #expect(reason(#"{"type":"share","items":[{"label":"Everest","value":-8849},{"label":"K2","value":8611}]}"#, "Everest -8849 K2 8611") == .badShare)
        #expect(reason(#"{"type":"share","items":[{"label":"Everest","value":0},{"label":"K2","value":0}]}"#, "Everest 0 K2 0") == .badShare)
        let nine = (1...9).map { #"{"label":"Everest","value":"# + "\($0)}" }.joined(separator: ",")
        // More than 8 parts is refused, not cut and drawn as the whole (V-7).
        #expect(reason(#"{"type":"share","items":["# + nine + "]}", "Everest 1 2 3 4 5 6 7 8 9") == .badShare)
    }

    // MARK: Grounding: numbers

    @Test func aNumberTheAnswerDoesntWriteIsRefusedWithTheNumber() {
        let r = Visual.parse(#"{"type":"bars","items":[{"label":"Everest","value":8849},{"label":"K2","value":8612}]}"#, answer: peaks)
        #expect(r == .rejected(.inventedNumbers, detail: "8612"))
    }

    @Test func numbersInsideTextAreCheckedToo() {
        #expect(reason(#"{"type":"facts","facts":[{"label":"Height","value":"8,850 m"}]}"#, peaks) == .inventedNumbers)
        #expect(reason(#"{"type":"table","columns":["Peak","Height"],"rows":[["Everest","9,000 m"],["K2","8,611 m"]]}"#, peaks) == .inventedNumbers)
        #expect(reason(#"{"type":"steps","steps":["Everest climbed in 1952","then K2"]}"#, peaks) == .inventedNumbers)
    }

    @Test func aComputedTotalOrPercentageIsRefused() {
        // 8849 + 8611 = 17460: the model added; the app computes totals, not the model.
        #expect(reason(#"{"type":"facts","facts":[{"label":"Everest and K2","value":"17,460 m"}]}"#, peaks) == .inventedNumbers)
        #expect(reason(#"{"type":"facts","facts":[{"label":"Everest share","value":"51%"}]}"#, peaks) == .inventedNumbers)
    }

    @Test func numbersWrittenInAnyUsualWayAreGrounded() {
        let ns = VisualCheck.numbersIn(pt)
        #expect(ns.contains(203.1) && ns.contains(203_100_000.0))
        #expect(ns.contains(146.4) && ns.contains(146_400_000.0))
        #expect(ns.contains(17_098_246.0))
        // A plain space doesn't join numbers ("K2 8611", validator V-1); a no-break space does.
        #expect(!VisualCheck.numbersIn("1 234 people").contains(1234.0))
        #expect(VisualCheck.numbersIn("1\u{00a0}234 people").contains(1234.0))
        #expect(VisualCheck.numbersIn("1,234 people").contains(1234.0))
        #expect(VisualCheck.numbersIn("3,5 graus").contains(3.5))
        #expect(VisualCheck.numbersIn("12% of it").contains(12.0))
        #expect(VisualCheck.numbersIn("1.5 million people").contains(1_500_000.0))
        #expect(VisualCheck.numbersIn("magnitude M9.5 quake").contains(9.5))
        // A list stays separate numbers, and a date's dashes aren't minus signs.
        #expect(Set(VisualCheck.numbersIn("in 1913, 1914").filter { $0 > 1000 }) == Set([1913.0, 1914.0]))
        let date = VisualCheck.numbersIn("on 1913-03-12")
        #expect(date.contains(3.0) && date.contains(12.0) && !date.contains(-3.0))
        #expect(VisualCheck.numbersIn("it fell to -4 degrees").contains(-4.0))
    }

    @Test func ptAnswersGroundTheirOwnNumbers() {
        let v = ok(#"{"type":"bars","title":"População","unit":"milhões","items":[{"label":"Brasil","value":203.1},{"label":"Rússia","value":146.4}]}"#, pt)
        #expect(series(v)?.items.count == 2)
    }

    @Test func aYearIsGroundedByAFullDateAndAFullDateNeedsItsDay() {
        #expect(VisualCheck.check(facts("", [("Everest first climbed", "1953")]), answer: peaks) == nil)
        #expect(VisualCheck.check(facts("", [("Everest first climbed", "29 May 1953")]), answer: peaks) == nil)
        #expect(VisualCheck.check(facts("", [("Everest first climbed", "1953")]), answer: "Everest was climbed on 1953-05-29.") == nil)
        #expect(VisualCheck.check(facts("", [("Everest first climbed", "28 May 1953")]), answer: peaks)?.0 == .inventedNumbers)
    }

    @Test func theUsersOwnNumbersCount() {
        let v = ok(#"{"type":"bars","items":[{"label":"Monday","value":5},{"label":"Tuesday","value":8}]}"#, "Here is the chart.", "Monday:5, Tuesday:8")
        #expect(series(v)?.items.count == 2)
    }

    // MARK: Grounding: labels

    @Test func aLabelWithNoWordFromTheAnswerIsRefused() {
        let r = Visual.parse(#"{"type":"bars","items":[{"label":"Everest","value":8849},{"label":"Aconcagua","value":8611}]}"#, answer: peaks)
        #expect(r == .rejected(.ungroundedLabels, detail: "Aconcagua"))
    }

    @Test func labelsMatchAcrossPluralsAccentsAndCase() {
        #expect(VisualCheck.check(.steps(.init("", ["Volcanoes erupt", "Magma rises"])), answer: "A volcano forms where magma rises.") == nil)
        #expect(VisualCheck.check(facts("", [("POPULACAO", "203,1 milhões")]), answer: pt) == nil)
        #expect(VisualCheck.check(facts("", [("Rússia", "146.4 milhões")]), answer: pt) == nil)
    }

    @Test func headingsAreTheModelsOwnWordsAndArentCheckedTheirNumbersAre() {
        #expect(VisualCheck.check(facts("A wholly new heading", [("Height", "8,849 m")]), answer: peaks) == nil)
        #expect(VisualCheck.check(.table(.init("", ["Peak", "Elevation"], [["Everest", "8,849 m"]])), answer: peaks) == nil)
        #expect(VisualCheck.check(facts("", [("Top 3 peaks", "Everest")]), answer: peaks)?.0 == .inventedNumbers)
        #expect(VisualCheck.check(facts("", [("Height", "Aconcagua")]), answer: peaks)?.0 == .ungroundedLabels)
    }

    // MARK: What the app computes

    @Test func sharesAddUpToExactly100() {
        #expect(VisualScale.percents([1.0, 1.0, 1.0]) == [34, 33, 33])
        #expect(VisualScale.percents([8849.0, 8611.0, 8586.0]).reduce(0, +) == 100)
        #expect(VisualScale.percents([5.0, 8.0, 10.0, 15.5]) == [13, 21, 26, 40])
        #expect(VisualScale.percents([0.0, 0.0]) == [0, 0])
    }

    @Test func axesStartAtZeroForBarsAndFitTheDataForALineAtRoundSteps() {
        let bars = VisualScale.axis([8586.0, 8611.0, 8849.0], fromZero: true)
        #expect(bars.min == 0.0 && bars.max == 10000.0 && bars.step == 2500.0)
        let line = VisualScale.axis([8586.0, 8611.0, 8849.0], fromZero: false)
        #expect(line.min <= 8586 && line.min > 8000)
        #expect(line.max >= 8849)
        #expect([1.0, 2.0, 2.5, 5.0].contains { abs(line.step / pow(10.0, log10(line.step).rounded(.down)) - $0) < 1e-9 })
        #expect(bars.ticks == [0.0, 2500.0, 5000.0, 7500.0, 10000.0])
        let flat = VisualScale.axis([5.0, 5.0], fromZero: false)
        #expect(flat.max > flat.min)
    }

    @Test func theSameDataSwitchesViewWithNoNewModelCall() {
        let s = Visual.Series("Peaks", .bars, "m", [VisualItem("Everest", 8849), VisualItem("K2", 8611), VisualItem("Kangchenjunga", 8586)])
        func with(_ kind: Visual.SeriesKind? = nil, _ items: [VisualItem]? = nil) -> Visual.Series {
            var c = s
            if let kind { c.kind = kind }
            if let items { c.items = items }
            return c
        }
        // A pie only for parts of a whole the model named (V-6): heights aren't shares.
        #expect(VisualScale.kinds(s) == ["bars", "line", "table"])
        #expect(VisualScale.kinds(with(.share)) == ["bars", "line", "share", "table"])
        #expect(VisualScale.kinds(with(.share, Array(s.items.prefix(2)))) == ["bars", "share", "table"])
        #expect(VisualScale.kinds(with(nil, [VisualItem("a", -1), VisualItem("b", 2), VisualItem("c", 3)])) == ["bars", "line", "table"])
        #expect(VisualScale.asKind(s, .line)?.kind == .line)
        #expect(VisualScale.asKind(with(nil, [VisualItem("a", -1), VisualItem("b", 2)]), .share) == nil)
        #expect(VisualScale.asTable(s).rows == [["Everest", "8849"], ["K2", "8611"], ["Kangchenjunga", "8586"]])
    }

    @Test func copyGivesPlainMarkdownSharesWithTheAppsPercents() {
        let share = Visual.series(.init("Stock", .share, nil, [VisualItem("Monday", 5), VisualItem("Tuesday", 8), VisualItem("Wednesday", 10), VisualItem("Thursday", 15.5)]))
        #expect(VisualScale.markdown(share) == "**Stock**\n\n- Monday: 5 (13%)\n- Tuesday: 8 (21%)\n- Wednesday: 10 (26%)\n- Thursday: 15.5 (40%)")
        let table = Visual.table(.init("", ["Peak", "Height"], [["Everest", "8,849 m"]]))
        #expect(VisualScale.markdown(table) == "| Peak | Height |\n| --- | --- |\n| Everest | 8,849 m |")
        #expect(VisualScale.markdown(.steps(.init("", ["a", "b"]))) == "1. a\n2. b")
    }

    @Test func numbersPrintWithoutTrailingZerosOrExponents() {
        #expect(VisualScale.format(1500.0) == "1500")
        #expect(VisualScale.format(3.25) == "3.25")
        #expect(VisualScale.format(2.031e8) == "203100000")
        #expect(VisualScale.format(-4.0) == "-4")
        // Past Kotlin's Long shortcut and below one: ten significant digits, written out.
        #expect(VisualScale.format(0.000125) == "0.000125")
        #expect(VisualScale.format(1.5e20) == "150000000000000000000")
        #expect(VisualScale.format(1.0 / 3.0) == "0.3333333333")
    }

    /// The X6's Brazil and Russia answer (Nov 10) and the table Qwen3-1.7B wrote from it, most of it from memory.
    private let x6Answer = "Brazil, on the other hand, is one of the ten chief industrial states in the world according to the International "
        + "Labour Organization. It has a population of approximately 210 million, making it the second-most populous country in the world. "
        + "Brazil's economy is more diversified. The country's nominal GDP was $2.642 trillion in 2024, and its GDP per capita was $12,313. "
        + "Brazil's economy is less dependent on a single sector compared to Russia's. Russia's economy is more volatile due to its reliance on oil and gas."
    private let x6Table = #"""
        {"type":"table","title":"Brazil and Russia compared: population, area and economy",
                "columns":["Country","Population (millions)","Area (km²)","Economy (Nominal GDP, $trillion)","Economy (GDP per capita, $)","Economy (Oil/Gas % of Budget)"],
                "rows":[["Brazil","210","8.5","2.642","12,313","30"],["Russia","140","11.5","2.642","11,633","50"]]}
        """#

    @Test func theX6TableKeepsWhatTheAnswerBacksAndSaysWhatItLeftOut() {
        guard let (v, leftOut) = okLeftOut(x6Table, x6Answer), let t = table(v) else { Issue.record("rejected"); return }
        #expect(t.columns == ["Country", "Population (millions)", "Economy (Nominal GDP, $trillion)", "Economy (GDP per capita, $)"])
        #expect(t.rows == [["Brazil", "210", "2.642", "12,313"]])
        #expect(["140", "11.5", "11,633", "50", "8.5", "30"].allSatisfy(leftOut.contains), "\(leftOut)")
    }

    @Test func aNumberInTheSourcesIsBackedTooSoItStays() {
        let sources = "Brazil covers an area of 8.5 million square kilometres."
        guard let (v, leftOut) = okLeftOut(x6Table, x6Answer + "\n" + sources) else { Issue.record("rejected"); return }
        #expect(table(v)?.columns.contains("Area (km²)") == true)
        #expect(!leftOut.contains("8.5"))
    }

    @Test func emptyCellsComeOutWithTheirLineNotLeftBlank() {
        let t = #"{"type":"table","title":"","columns":["Country","Population","Area"],"rows":[["Brazil","210 million",""],["Russia","146 million",""]]}"#
        let v = table(ok(t, "Brazil has 210 million people and Russia 146 million."))
        #expect(v?.columns == ["Country", "Population"])
        #expect(v?.rows.count == 2)
    }

    @Test func aChartDropsTheItemNotInTheTextsAndKeepsTheRest() {
        let raw = #"{"type":"bars","unit":"m","items":[{"label":"Everest","value":8849},{"label":"K2","value":8611},{"label":"Kangchenjunga","value":8600}]}"#
        guard let (v, leftOut) = okLeftOut(raw, peaks) else { Issue.record("rejected"); return }
        #expect(series(v)?.items.map(\.label) == ["Everest", "K2"])
        #expect(leftOut == ["8600"])
    }

    @Test func tooLittleLeftIsStillRefusedWithWhatFailedFirst() {
        #expect(Visual.parse(#"{"type":"bars","items":[{"label":"Everest","value":8849},{"label":"K2","value":8612}]}"#, answer: peaks)
            == .rejected(.inventedNumbers, detail: "8612"))
        let all = #"{"type":"table","columns":["Country","Area"],"rows":[["Brazil","8.5"],["Russia","11.5"]]}"#
        #expect(reason(all, x6Answer) == .inventedNumbers)
    }

    @Test func aUnitMustComeFromTheAnswerToo() {
        let answer = "Brazil's GDP was $2.642 trillion and Russia's $2.2 trillion. Brazil covers 8,515,767 km²."
        let gdp = #"{"type":"bars","title":"GDP","unit":"trillion US$","items":[{"label":"Brazil","value":2.642},{"label":"Russia","value":2.2}]}"#
        #expect(isOk(gdp.replacingOccurrences(of: "trillion US$", with: "trillion $"), answer))
        #expect(reason(gdp.replacingOccurrences(of: "trillion US$", with: "billion $"), answer) == .ungroundedLabels)
        #expect(reason(gdp.replacingOccurrences(of: "trillion US$", with: "trillion €"), answer) == .ungroundedLabels)
        #expect(VisualCheck.unitOk("km²", answer))
        #expect(VisualCheck.unitOk("trillion", answer))
        #expect(!VisualCheck.unitOk("million km²", answer))
        #expect(VisualCheck.unitOk("milhões", "A população é de 203,1 milhões."))
        #expect(VisualCheck.unitOk("m", "Mount Everest is 8,849 m high."))
    }

    @Test func thePromptPutsTheRulesFirstUnitsIncludedAndLetsAMissingValueStayEmpty() {
        let p = Visual.prompt
        #expect(p.range(of: "STRICT RULES")!.lowerBound < p.range(of: "\"type\":\"bars\"")!.lowerBound)
        #expect(p.contains("empty string"))
        #expect(p.contains("at most 3 columns"))
        #expect(p.contains("Never convert units"))
        #expect(!p.contains("another country"))
    }

    @Test func thePromptAsksForDataNeverForComputedNumbers() {
        let p = Visual.prompt
        #expect(p.contains("\"type\":\"line\""))
        #expect(p.contains("\"type\":\"share\""))
        #expect(p.contains("no percentages"))
        #expect(p.contains("{\"type\":\"none\"}"))
        #expect(!p.contains("timeline"))
    }

    // MARK: Validator gate, Nov 10

    @Test func v1ASpaceDoesntJoinTwoNumbers() {
        let ns = VisualCheck.numbersIn("K2 8611 m and Apollo 11 1969")
        #expect(ns.contains(8611.0) && ns.contains(2.0) && ns.contains(11.0) && ns.contains(1969.0))
        #expect(!ns.contains(2861.0))
        #expect(VisualCheck.numbersIn("1\u{00a0}234 people").contains(1234.0))
        #expect(VisualCheck.numbersIn("1\u{202f}234 people").contains(1234.0))
        // The old saved K2 card reads again.
        #expect(isOk(#"{"type":"bars","unit":"m","items":[{"label":"Everest","value":8849},{"label":"K2","value":8611}]}"#, "Everest is 8,849 m and K2 8611 m."))
    }

    @Test func v2ANumberIsReadTheWayItsWritten() {
        #expect(VisualCheck.readings("3,5") == [3.5])
        #expect(VisualCheck.readings("1,234") == [1234.0])
        #expect(VisualCheck.readings("1.5") == [1.5])
        #expect(VisualCheck.readings("1.234") == [1.234, 1234.0])
        #expect(VisualCheck.readings("1.234.567") == [1234567.0])
        #expect(VisualCheck.readings("1.234,5") == [1234.5])
        #expect(!VisualCheck.numbersIn("3,5 graus").contains(35.0))
        #expect(!VisualCheck.numbersIn("1,5 milhão").contains(15.0))
        #expect(VisualCheck.numbersIn("1,5 milhão").contains(1_500_000.0))
        #expect(!VisualCheck.numbersIn("1.5 million").contains(15_000_000.0))
        // A value written as text in the reply is read the same way.
        let v = series(ok(#"{"type":"bars","unit":"graus","items":[{"label":"Lisboa","value":"3,5"},{"label":"Porto","value":"2,5"}]}"#, "Lisboa 3,5 graus, Porto 2,5 graus."))
        #expect(v?.items.map(\.value) == [3.5, 2.5])
    }

    @Test func v3ANumberMustStandByItsOwnLabel() {
        let answer = "Paris has 2.1 million people, Lyon 0.5 million."
        let swapped = #"{"type":"bars","unit":"million","items":[{"label":"Paris","value":0.5},{"label":"Lyon","value":2.1}]}"#
        #expect(reason(swapped, answer) == .unpaired)
        let right = #"{"type":"bars","unit":"million","items":[{"label":"Paris","value":2.1},{"label":"Lyon","value":0.5}]}"#
        #expect(isOk(right, answer))
        // The X6 table still keeps Brazil's row: "It has 210 million" names Brazil a sentence before.
        let rows = okLeftOut(x6Table, x6Answer).flatMap { table($0.0) }?.rows
        #expect(rows?.count == 1 && rows?.first?.first == "Brazil")
        // A table row swapped with another's number is left out.
        let t = #"{"type":"table","columns":["City","People"],"rows":[["Paris","0.5 million"],["Lyon","2.1 million"],["Marseille","0.9 million"]]}"#
        #expect(reason(t, answer + " Marseille 0.9 million.") == .unpaired)
    }

    // Validator, Nov 11: correct data written number-first was refused, and so were labels that are prefixes of others.
    @Test func v3TheNumberBeforeItsNameIsPairedWithThatNameAndASwapIsStillRefused() {
        func bars(_ a: Double, _ b: Double, _ la: String = "Paris", _ lb: String = "Lyon", unit: String = "million") -> String {
            #"{"type":"bars","unit":""# + unit + #"","items":[{"label":""# + la + #"","value":"# + "\(a)" + #"},{"label":""# + lb + #"","value":"# + "\(b)" + "}]}"
        }
        for answer in ["2.1 million people live in Paris and 0.5 million in Lyon.", "2.1 million (Paris), 0.5 million (Lyon)."] {
            #expect(isOk(bars(2.1, 0.5), answer), "\(answer)")
            #expect(reason(bars(0.5, 2.1), answer) == .unpaired, "\(answer)")
        }
        let pt = "2,1 milhões de pessoas vivem em Paris e 0,5 milhão em Lyon."
        #expect(isOk(bars(2.1, 0.5, unit: "milhões"), pt))
        #expect(reason(bars(0.5, 2.1, unit: "milhões"), pt) == .unpaired)
        // Name first still works both ways.
        let nameFirst = "Paris has 2.1 million people, Lyon 0.5 million."
        #expect(isOk(bars(2.1, 0.5), nameFirst))
        #expect(reason(bars(0.5, 2.1), nameFirst) == .unpaired)
    }

    // Validator Q-A3 (t9 0115): one sentence per item, each starting with its number, refused the right card 3 of 3.
    @Test func qA3ASentenceThatStartsWithItsNumberIsItsOwnAndASwapIsStillRefused() {
        func bars(_ p: (String, Double)...) -> String {
            #"{"type":"bars","unit":"million","items":["# + p.map { #"{"label":""# + $0.0 + #"","value":"# + "\($0.1)}" }.joined(separator: ",") + "]}"
        }
        let three = "2.1 million people live in Paris. 0.5 million people live in Lyon. 0.9 million people live in Marseille."
        #expect(isOk(bars(("Paris", 2.1), ("Lyon", 0.5), ("Marseille", 0.9)), three))
        #expect(reason(bars(("Paris", 0.5), ("Lyon", 2.1), ("Marseille", 0.9)), three) == .unpaired)
        #expect(reason(bars(("Paris", 2.1), ("Lyon", 0.9), ("Marseille", 0.5)), three) == .unpaired)
        // Mixed orders, each sentence its own (CodeRabbit on all73).
        let mixed = "Paris has 2.1 million people. 0.5 million people live in Lyon. Marseille has 0.9 million people."
        #expect(series(ok(bars(("Paris", 2.1), ("Lyon", 0.5), ("Marseille", 0.9)), mixed))?.items.count == 3)
        #expect(reason(bars(("Paris", 0.5), ("Lyon", 2.1), ("Marseille", 0.9)), mixed) == .unpaired)
        let two = "2.1 million people live in Paris. 0.5 million live in Lyon."
        #expect(isOk(bars(("Paris", 2.1), ("Lyon", 0.5)), two))
        #expect(reason(bars(("Paris", 0.5), ("Lyon", 2.1)), two) == .unpaired)
    }

    @Test func v3ALabelInsideALongerOneIsntConfusedWithIt() {
        let sudan = "South Sudan has 11 million people and Sudan has 48 million."
        #expect(isOk(#"{"type":"bars","unit":"million","items":[{"label":"Sudan","value":48},{"label":"South Sudan","value":11}]}"#, sudan))
        #expect(reason(#"{"type":"bars","unit":"million","items":[{"label":"Sudan","value":11},{"label":"South Sudan","value":48}]}"#, sudan) == .unpaired)
        let parts = "Part10 weighs 40 kg and Part1 weighs 7 kg."
        #expect(isOk(#"{"type":"bars","unit":"kg","items":[{"label":"Part1","value":7},{"label":"Part10","value":40}]}"#, parts))
        #expect(reason(#"{"type":"bars","unit":"kg","items":[{"label":"Part1","value":40},{"label":"Part10","value":7}]}"#, parts) == .unpaired)
    }

    @Test func v4ANumberInTheTitleOrTheUnitMustBeBackedToo() {
        #expect(reason(#"{"type":"bars","title":"Peaks in 2099","unit":"m","items":[{"label":"Everest","value":8849},{"label":"K2","value":8611}]}"#, peaks) == .inventedNumbers)
        #expect(reason(#"{"type":"bars","unit":"per 2099 m","items":[{"label":"Everest","value":8849},{"label":"K2","value":8611}]}"#, peaks) == .inventedNumbers)
        #expect(isOk(#"{"type":"bars","title":"Climbed since 1953","unit":"m","items":[{"label":"Everest","value":8849},{"label":"K2","value":8611}]}"#, peaks))
    }
}
