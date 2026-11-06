import BoarCore
import SwiftUI

/// One "book cover" in the welcome step's fanned stack: the symbol and title on top (they stay readable where the next
/// cover overlaps), the one-line description below.
struct LibraryCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let fill: Color
    let ink: Color
    var width: CGFloat = 236
    var height: CGFloat = 150
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
                    .boarText("ui.titleLg")
            } icon: {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(detail)
                .boarText("ui.subtext")
                .opacity(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .padding(16)
        .frame(width: width, height: height, alignment: .leading)
        // Opaque: the tint sits on the screen background so the covers behind never show through.
        .background {
            RoundedRectangle(cornerRadius: 18).fill(Color(palette.bgTerminal))
            RoundedRectangle(cornerRadius: 18).fill(fill)
        }
        .accessibilityElement(children: .combine)
    }
}
