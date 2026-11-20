import Foundation
import Testing

@testable import BoarAnswer

/// t9 2200 d: a table in an answer shows as lines, not raw pipes (android TableLinesTest.kt).
struct TableLinesTests {
    private let blood = "Blood test results — March 2026\n\n| Test | Result | Reference |\n|---|---|---|\n| Fasting glucose | 98 mg/dL | 70 to 99 mg/dL |\n"
        + "| Total cholesterol | 231 mg/dL | below 190 mg/dL |\n| LDL | 162 mg/dL | below 130 mg/dL |\n\nNote from Dr. Helen Price: LDL above target."

    @Test func aTablesRowsBecomeFirstSecondThirdLinesTheRestUntouched() {
        #expect(TableLines.of(blood) == "Blood test results — March 2026\n\nFasting glucose: 98 mg/dL (70 to 99 mg/dL)\nTotal cholesterol: 231 mg/dL (below 190 mg/dL)\n"
            + "LDL: 162 mg/dL (below 130 mg/dL)\n\nNote from Dr. Helen Price: LDL above target.")
        #expect(!TableLines.of(blood).contains("|"))
    }

    @Test func textWithoutATableOrAPipeThatIsntOneStaysAsItWas() {
        for t in ["No table here.", "a | b in a sentence", "| only one row |", "x || y"] { #expect(TableLines.of(t) == t) }
        #expect(TableLines.of("| Name | Value |\n| --- | --- |\n| A | 1 |\n| B | 2 |") == "A: 1\nB: 2")
    }

    @Test func aOneCellRowAndCrlfLines() {
        #expect(TableLines.of("| H | I |\r\n|---|---|\r\n| only |\r\nafter") == "only\nafter")
    }

    /// The Kotlin test reads Markdown.kt; here the Markdown renderer (text between code blocks only).
    @Test func theChatDrawsAnswersThroughIt() throws {
        let md = try Fixtures.text(Fixtures.root.appending(path: "App/Features/Chat/MarkdownBlocks.swift"))
        #expect(md.contains("let s = TableLines.of(text)"))
    }
}
