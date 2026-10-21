import SwiftUI

/// A finished answer's process, collapsed into the same card the steps ran in: "Searched 3 sources · 21 s", opening to
/// what BOAR did and how long each part took, then the numbered sources (each opens the passage the model read).
struct SourcesList: View {
    let message: ChatItem
    let technicalDetails: Bool
    let onOpen: (ChatSource) -> Void
    @State private var expanded = false

    private var duration: String? {
        guard let s = message.answerSeconds ?? message.receipt.map({ $0.totalMs / 1000 }) else { return nil }
        return Duration.seconds(max(1, s.rounded())).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    var body: some View {
        if !message.sources.isEmpty || (duration != nil && !message.text.isEmpty) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if let receipt = message.receipt {
                        steps(receipt)
                    }
                    if !message.sources.isEmpty {
                        Text("Sources")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(message.sources) { source in
                            SourceButton(source: source, technicalDetails: technicalDetails, onOpen: onOpen)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label {
                    title
                } icon: {
                    Image(systemName: message.sources.isEmpty ? "clock" : Symbols.sources)
                }
                .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .tint(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }

    /// The parts of the answer the receipt measured, in the order they ran.
    @ViewBuilder private func steps(_ receipt: Receipt) -> some View {
        if let load = receipt.loadMs { row("Loaded the model", load) }
        if let search = receipt.retrievalMs {
            row(message.sources.isEmpty ? "Searched your library" : "Found ^[\(message.sources.count) source](inflect: true)", search)
        }
        if let prefill = receipt.prefillMs { row("Read the sources", prefill) }
        row("Wrote ~\(Receipt.words(Double(receipt.tokens))) words", max(0, receipt.totalMs - receipt.ttftMs))
    }

    private func row(_ title: LocalizedStringKey, _ ms: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Text(Receipt.seconds(ms))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
    }

    private var title: Text {
        let n = message.sources.count
        if n == 0, let duration { return Text("Answered in \(duration)") }
        if let duration { return Text("Searched ^[\(n) source](inflect: true) · \(duration)") }
        return Text("^[\(n) source](inflect: true)")
    }
}
