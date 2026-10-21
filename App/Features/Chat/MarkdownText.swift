import SwiftUI

/// An answer's text (port of android `MarkdownMessage`, itself components/MarkdownMessage.tsx): ``` code blocks,
/// # / ## / ### headings, "- " and "* " bullets, numbered lines, and inline markdown (`code`, **bold**, *italic*, links)
/// through `AttributedString`. Citations "[n]" become links to `boar-source://n`, which the chat opens as the passage.
struct MarkdownText: View {
    let text: String
    /// Citations past this count stay plain text (cleanCitations already dropped invented ones once the answer ended).
    let sourceCount: Int
    /// The answer the citations belong to (their links carry it).
    var answerId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, sourceCount: sourceCount, answerId: answerId)
            }
        }
        .textSelection(.enabled)
    }
}
