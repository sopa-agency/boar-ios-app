import Foundation
import Testing

@testable import BoarAnswer

/// LabRangesTest.kt: a fictional blood test, marked in code; the summary instruction.
struct LabRangesTests {
    private typealias Mark = LabRanges.Mark

    private let blood = "Blood test results — March 2026\n\nPatient: Anna Reed (fictional document, for BOAR tests). Vida Clinical Lab.\n\n"
        + "| Test | Result | Reference |\n|---|---|---|\n| Fasting glucose | 98 mg/dL | 70 to 99 mg/dL |\n| Total cholesterol | 231 mg/dL | below 190 mg/dL |\n"
        + "| LDL | 162 mg/dL | below 130 mg/dL |\n| HDL | 48 mg/dL | above 40 mg/dL |\n| Triglycerides | 140 mg/dL | below 150 mg/dL |\n| Vitamin D | 24 ng/mL | 30 to 100 ng/mL |\n\n"
        + "Note from Dr. Helen Price: LDL above target; repeat in 6 months, with diet changes and daily walks."

    @Test func eachResultMarkedAsTheLabWould() {
        let rows = LabRanges.rows(blood)
        #expect(rows.map(\.name) == ["Fasting glucose", "Total cholesterol", "LDL", "HDL", "Triglycerides", "Vitamin D"])
        #expect(rows.map(\.mark) == [Mark.within, .above, .above, .within, .within, .below])
        // Values and ranges as written, units kept.
        #expect(rows[1].value == "231 mg/dL" && rows[1].range == "below 190 mg/dL")
    }

    @Test func theSameInPortugueseAndAsLines() throws {
        let pt = "Exame de sangue\n| Exame | Resultado | Referência |\n|---|---|---|\n| Glicose | 98 mg/dL | de 70 a 99 mg/dL |\n"
            + "| Colesterol total | 231 mg/dL | abaixo de 190 mg/dL |\n| HDL | 48 mg/dL | acima de 40 mg/dL |\n| Vitamina D | 24 ng/mL | 30 a 100 ng/mL |"
        #expect(LabRanges.rows(pt).map(\.mark) == [Mark.within, .above, .within, .below])
        let lines = "- LDL: 162 mg/dL (below 130 mg/dL)\n- HDL: 48 mg/dL (above 40 mg/dL)"
        #expect(LabRanges.rows(lines).map(\.mark) == [Mark.above, .within])
        // Golden change (Android d63ebee2): the range as a reference, so "ACIMA da faixa de abaixo de 190" isn't read into it.
        #expect(try #require(LabRanges.note(pt, pt: true)).contains("Colesterol total: 231 mg/dL, ACIMA da faixa (ref. abaixo de 190 mg/dL)"))
        #expect(try #require(LabRanges.note(blood, pt: false)).contains("231 mg/dL, ABOVE its range (ref. below 190 mg/dL)"))
    }

    @Test func aRowTheCodeCantReadIsLeftUnmarked() throws {
        #expect(LabRanges.mark(value: "231 mg/dL", range: "see your doctor") == nil)
        #expect(LabRanges.mark(value: "6.0 mmol/L", range: "below 190 mg/dL") == nil)
        #expect(LabRanges.mark(value: "positive", range: "negative") == nil)
        #expect(LabRanges.note("No results here, just a note.", pt: false) == nil)
        // The block says it is BOAR's, not the file's.
        #expect(try #require(LabRanges.note(blood, pt: false)).hasPrefix("Computed by BOAR from this file's own numbers (not written in the file)"))
    }

    /// Android also reads ChatViewModel; here the same wiring in ChatController (the app target has no unit tests).
    @Test func aSummaryAsksForTheModelsWordsAndTheCodesMarks() throws {
        for q in ["hows health blood test? summarize", "summarize my blood test", "resuma meu exame de sangue", "me dá um resumo do exame"] {
            #expect(PersonalFiles.asksSummary(q), "\(q)")
        }
        #expect(!PersonalFiles.asksSummary("what is my LDL?"))
        #expect(PersonalFiles.summaryEN.contains("never copy the file") && PersonalFiles.summaryEN.contains("say that mark exactly"))
        let chat = try Fixtures.text(Fixtures.root.appending(path: "App/Sources/Model/ChatController.swift"))
        #expect(chat.contains("personal && PersonalFiles.asksSummary(q)"))
        #expect(chat.contains("LabRanges.note(c.body, pt: ptQ)"))
        // A Personal Files health answer keeps the files-only prompt, kept short by a reminder (Android aa9b0cc5).
        #expect(chat.contains("let style = shortReason != nil && !personal ? \"succinct\" : chosenStyle"))
        #expect(chat.contains("personal && shortReason != nil ? ShortAnswer.personalShort : nil"))
    }
}

/// LabRangesSafetyTest (validator 04:25, t9 0435): never guess a direction when the numbers or units don't line up.
struct LabRangesSafetyTests {
    private typealias Mark = LabRanges.Mark
    private func m(_ v: String, _ r: String, _ ctx: String = "") -> Mark? { LabRanges.mark(value: v, range: r, context: ctx) }

    @Test func aThousandsMarkTheFileDoesntExplainLeavesTheRowUnmarked() {
        for (v, r) in [("1.250 mg/dL", "abaixo de 150"), ("1,250 mg/dL", "below 150"), ("1.500", "< 200"), ("2.000", "até 200"),
                       ("1.350 ng/mL", "30 - 400"), ("1.200", "acima de 30")] {
            #expect(m(v, r) == nil, "\(v) | \(r)")
        }
        // Plain decimals still read: 6,5 against 4,0 a 7,0.
        #expect(m("6,5", "4,0 a 7,0") == .within)
    }

    @Test func aValueOnAnInclusiveBoundIsWithinIt() {
        for r in ["≤190", "<= 190", "até 190", "up to 190"] { #expect(m("190", r) == .within, "\(r)") }
        for r in ["≥ 40", ">=40", "pelo menos 40", "at least 40"] { #expect(m("40", r) == .within, "\(r)") }
        #expect(m("190", "below 190") == .above)
        #expect(m("40", "above 40") == .below)
    }

    @Test func aUnitAgainstARangeWithoutOneIsMarkedOnlyWhenTheHeaderNamesIt() {
        #expect(m("6,5 mmol/L", "abaixo de 190") == nil)
        #expect(m("5,4 mmol/L", "70 - 99") == nil)
        #expect(m("98 mg/dL", "70 - 99", "| Exame | Resultado | Referência (mg/dL) |") == .within)
        let table = "| Exam | Result | Reference (mg/dL) |\n|---|---|---|\n| Glucose | 98 mg/dL | 70 - 99 |\n| Cholesterol | 6,5 mmol/L | below 190 |"
        #expect(LabRanges.rows(table).map(\.name) == ["Glucose"])
    }

    @Test func anEmptyCellKeepsItsPlaceInATableShownAsLines() {
        #expect(TableLines.of("| Exame | Resultado | Referência |\n|---|---|---|\n| Glicose | | 70 - 99 mg/dL |") == "Glicose: — (70 - 99 mg/dL)")
    }
}
