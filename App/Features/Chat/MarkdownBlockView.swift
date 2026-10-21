import SwiftUI

/// One parsed block of an answer: code, a heading, a bullet or numbered line, or a paragraph.
struct MarkdownBlockView: View {
    let block: MarkdownBlocks.Block
    let sourceCount: Int
    var answerId: String? = nil

    var body: some View {
        switch block {
        case .code(let code, let language):
            VStack(alignment: .leading) {
                if !language.isEmpty {
                    Text(language.uppercased()).font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(code).font(.callout.monospaced())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        case .heading(let level, let content):
            Text(inline(content))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .accessibilityAddTraits(.isHeader)
        case .bullet(let marker, let content):
            HStack(alignment: .firstTextBaseline) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(marker == "•")
                Text(inline(content))
            }
        case .paragraph(let content):
            Text(inline(content))
        }
    }

    private func inline(_ s: String) -> AttributedString {
        MarkdownBlocks.inline(s, sourceCount: sourceCount, answerId: answerId)
    }
}
