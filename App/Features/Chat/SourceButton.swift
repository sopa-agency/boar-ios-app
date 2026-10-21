import SwiftUI

/// One numbered source: its number and title (and the match with technical details on), opening the passage.
struct SourceButton: View {
    let source: ChatSource
    let technicalDetails: Bool
    let onOpen: (ChatSource) -> Void

    private var symbol: String { source.number <= 50 ? "\(source.number).circle" : "number.circle" }

    var body: some View {
        Button(action: open) {
            HStack {
                Label {
                    Text(source.title).lineLimit(1)
                } icon: {
                    Image(systemName: symbol)
                }
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if technicalDetails, let sim = source.similarity {
                    Text(sim, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Source \(source.number): \(source.title)"))
        .accessibilityHint(Text("Shows the passage BOAR read"))
    }

    private func open() {
        onOpen(source)
    }
}
