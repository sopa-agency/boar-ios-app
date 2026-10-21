import BoarAnswer
import SwiftUI

/// One answer style: its symbol, name and what it does, with a checkmark on the current one.
struct ToneRow: View {
    let tone: Personality
    let selected: Bool
    let onSelect: (String) -> Void

    /// The native app's wording where it differs from the shared catalog.
    private var detail: String { Self.detail(for: tone) }

    static func detail(for tone: Personality) -> String {
        tone.id == "succinct" ? String(localized: "Fastest. A few short paragraphs, straight to the point.") : tone.description
    }

    var body: some View {
        Button(action: select) {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(tone.label)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: tone.symbol)
                }
                Spacer()
                if selected {
                    Image(systemName: Symbols.active)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select() {
        onSelect(tone.id)
    }
}
