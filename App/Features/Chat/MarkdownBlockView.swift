import BoarCore
import SwiftUI

/// One parsed block of an answer: code, a heading, a bullet or numbered line, or a paragraph.
struct MarkdownBlockView: View {
    let block: MarkdownBlocks.Block
    let sourceCount: Int
    var answerId: String? = nil
    @Environment(\.palette) private var palette

    var body: some View {
        switch block {
        case .code(let code, let language):
            VStack(alignment: .leading) {
                if !language.isEmpty {
                    Text(language.uppercased()).boarText("mono.xs").foregroundStyle(Color(palette.textMuted))
                }
                ScrollView(.horizontal) {
                    Text(code).font(.callout.monospaced()).foregroundStyle(Color(palette.textPrimary))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(palette.bgBlack), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(palette.borderDefault)) }
        case .heading(let level, let content):
            // Android: # titleLg and ## title in the heading color, ### titleSm in the second accent.
            Text(inline(content))
                .boarText(level == 1 ? "ui.titleLg" : level == 2 ? "ui.title" : "ui.titleSm")
                .foregroundStyle(Color(level >= 3 ? palette.textAccentCyan : palette.textHeading))
                .padding(.top, level == 1 ? 8 : level == 2 ? 6 : 4)
                .accessibilityAddTraits(.isHeader)
        case .bullet(let marker, let content):
            HStack(alignment: .firstTextBaseline) {
                Text(marker)
                    .fontWeight(marker == "•" ? .heavy : .regular)
                    .foregroundStyle(Color(marker == "•" ? palette.textAccentEmerald : palette.textMuted))
                    .accessibilityHidden(marker == "•")
                Text(inline(content))
            }
            .boarText("ui.bodyLg")
        case .paragraph(let content):
            Text(inline(content))
                .boarText("ui.bodyLg")
        }
    }

    private func inline(_ s: String) -> AttributedString {
        MarkdownBlocks.inline(s, sourceCount: sourceCount, answerId: answerId)
    }
}
