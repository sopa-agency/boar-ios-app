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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(detail)
                .font(.footnote)
                .opacity(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .padding(16)
        .frame(width: width, height: height, alignment: .leading)
        // Opaque: the tint sits on the system background so the covers behind never show through.
        .background {
            RoundedRectangle(cornerRadius: 18).fill(Color.baseBackground)
            RoundedRectangle(cornerRadius: 18).fill(fill)
        }
        .accessibilityElement(children: .combine)
    }
}
