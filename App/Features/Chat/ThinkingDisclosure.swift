import SwiftUI

/// A thinking model's reasoning, collapsed: "Thinking…" while it reasons, "Thought for 12 s" after.
struct ThinkingDisclosure: View {
    let thinking: String
    let active: Bool
    /// The reply ended (stopped or out of room) before the reasoning did.
    let unfinished: Bool
    let seconds: Double?
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(thinking)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label {
                title
            } icon: {
                Image(systemName: Symbols.thinking)
                    .symbolEffect(.pulse, isActive: active)
            }
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .tint(.secondary)
    }

    private var title: Text {
        if active { return Text("Thinking…") }
        if unfinished { return Text("Stopped While Thinking") }
        guard let seconds else { return Text("Thought Process") }
        let d = Duration.seconds(max(1, seconds.rounded()))
        return Text("Thought for \(d.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))")
    }
}
