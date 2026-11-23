import Testing

/// android `engine/chat/ReceiptLeftTest.kt` and `PluginNotesFooterTest.kt` (adam, Nov 14), which read the chat's Kotlin
/// source: here `AnswerFooter.swift`, `AnswerView.swift` and `Labs.swift`. Differences: the footer has no 💭 button (iOS
/// shows the reasoning in its own disclosure above the answer), and Designer's failure note isn't ported (no Designer).
struct AnswerFooterTests {
    private func footer() throws -> String { try AppSource.text("App/Features/Chat/AnswerFooter.swift") }

    @Test func theReceiptStartsTheFooterRowTheButtonsAfterItOnTheRight() throws {
        let row = try AppSource.slice(footer(), after: "// The receipt on the left, filling the row up to the buttons.", before: "moreMenu\n")
        #expect(row.contains("ReceiptButton(receipt: receipt") && row.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(try #require(row.range(of: "ReceiptButton(")).lowerBound < #require(row.range(of: "Button(\"Copy\"")).lowerBound)
        // Everyone sees the time and speed; the measured details open only with technical details on.
        #expect(row.contains("opens: chat.technicalDetails"))
        let receipt = try AppSource.text("App/Features/Chat/ReceiptButton.swift")
        #expect(receipt.contains(".multilineTextAlignment(.leading)") && !receipt.contains(".trailing"))
        // The rating is hidden, its code kept (android SHOW_RATING).
        #expect(try footer().contains("private static let showRating = false") && footer().contains("if Self.showRating {"))
    }

    @Test func theAnswersNotesSitUnderTheSeparatorAboveTheReceiptRow() throws {
        let f = try footer()
        let body = try AppSource.slice(f, after: "var body: some View {", before: "    /// BOAR's notes first")
        let separator = try #require(body.range(of: ".frame(height: 0.5)")).lowerBound
        let notes = try #require(body.range(of: "            notes\n")).lowerBound
        let receipt = try #require(body.range(of: "ReceiptButton(")).lowerBound
        #expect(separator < notes && notes < receipt)
        // The style note, the number check and the no-source line are in the footer, once, and no longer in the answer.
        let notesBody = try AppSource.slice(f, after: "@ViewBuilder private var notes: some View {", before: "\n    }\n")
        #expect(notesBody.contains("message.receipt?.styleNote") && notesBody.contains("StagedCheck(staged: staged)") && notesBody.contains("NoSource.shows("))
        let answer = try AppSource.text("App/Features/Chat/AnswerView.swift")
        #expect(!answer.contains("StagedCheck(") && !answer.contains("NoSource.shows(") && !answer.contains("receipt?.styleNote"))
    }

    @Test func pluginNotesSitAfterBoarsOwnBeforeTheReceiptRow() throws {
        let notesBody = try AppSource.slice(footer(), after: "@ViewBuilder private var notes: some View {", before: "\n    }\n")
        #expect(try #require(notesBody.range(of: "StagedCheck(staged: staged)")).lowerBound < #require(notesBody.range(of: "Labs.shared.answerNotes(answerRef)")).lowerBound)
        #expect(try #require(notesBody.range(of: "NoSource.shows(")).lowerBound < #require(notesBody.range(of: "Labs.shared.answerNotes(answerRef)")).lowerBound)
        // An error in the color the chat uses for errors.
        #expect(notesBody.contains("note.error ? .boar(.danger) : .boar(.muted)"))
    }

    @Test func oldestFirstSoANewNoteIsTheLastLine() throws {
        let labs = try AppSource.text("App/Features/Labs/Labs.swift")
        let hook = try AppSource.slice(labs, after: "func answerNotes(_ answer: AnswerRef) -> [LabAnswerNote] {\n", before: "\n    }\n")
        #expect(hook.contains("($0.element.at, $0.offset) < ($1.element.at, $1.offset)"))
        // The slot exists on a lab with a default of none.
        #expect(labs.contains("func answerNotes(_ answer: AnswerRef) -> [LabAnswerNote] { [] }"))
    }
}
