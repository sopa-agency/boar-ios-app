import BoarAnswer
import SwiftUI

/// One answer style: its symbol, name and what it does, with a checkmark on the current one.
struct ToneRow: View {
    let tone: Personality
    let selected: Bool
    let onSelect: (String) -> Void

    private var detail: String { Self.detail(for: tone) }

    /// Android's wording since rc2 (Succinct no longer says "Default for mobile"), so no native override is left.
    static func detail(for tone: Personality) -> String { tone.description }

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
