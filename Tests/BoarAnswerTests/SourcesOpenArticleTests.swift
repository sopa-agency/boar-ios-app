import Testing

/// android `engine/rag/SourcesLayoutTest.kt` (5c0f04fe, adam Nov 12), the tests that read the chat's Kotlin source: here the
/// app's Swift source. One design for everyone: a tap on a source, a quote or an [n] opens the article at the passage, with
/// no passage sheet between; back (closing the sheet) leaves the chat where it was. Not ported: the "block above the answer"
/// (`SourcesAbove`, 35 % of the screen, folds per answer) and Android's `ChatScroll`: iOS keeps its sources in the steps card
/// under the question, and the reader is a sheet over the chat, which keeps its scroll while it is open.
struct SourcesOpenArticleTests {
    @Test func aTapOnASourceAQuoteOrAnNOpensTheSameSheet() throws {
        let answer = try AppSource.text("App/Features/Chat/AnswerView.swift")
        // The numbered source, the quote and the citation all go to `onOpenSource`.
        #expect(try AppSource.slice(answer, after: "private func openQuote(", before: "\n    }").contains("onOpenSource(ChatSource("))
        #expect(try AppSource.slice(answer, after: "private func openCitation(", before: "\n    }").contains("onOpenSource(message.sources[n - 1])"))
        #expect(answer.contains("SourcesList(message: message, technicalDetails: chat.technicalDetails, onOpen: onOpenSource)"))
        let view = try AppSource.text("App/Features/Chat/ChatView.swift")
        #expect(view.contains(".sheet(item: $openSource) { source in") && view.contains("SourceSheet(source: source"))
    }

    @Test func theSheetIsTheArticleAtThePassageNotAPassageSheetWithAButton() throws {
        let sheet = try AppSource.text("App/Features/Chat/SourceSheet.swift")
        let content = try AppSource.slice(sheet, after: "@ViewBuilder private var content: some View {", before: "\n    }\n")
        #expect(content.contains("if source.docId != nil {") && content.contains("SourceReader(source: source)"))
        // No "Read the whole article" step in between.
        #expect(!sheet.contains("Read the Whole Article") && !sheet.contains("navigationDestination"))
        // The reader scrolls to the passage it's given and marks it.
        let reader = try AppSource.text("App/Features/Chat/SourceReader.swift")
        #expect(reader.contains("SourceArticle.passageAt(text, passage)") && reader.contains("proxy.scrollTo(\"used\""))
    }
}
