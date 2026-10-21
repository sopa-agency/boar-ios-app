#if os(macOS)
import SwiftUI

/// The chat's trailing inspector on the Mac: every source of the answer you looked at, the one you opened expanded to
/// the exact passage the model read. It stays open beside the answer instead of a sheet over it.
struct SourceInspector: View {
    let sources: [ChatSource]
    @Binding var selected: ChatSource?
    let technicalDetails: Bool

    var body: some View {
        Group {
            if sources.isEmpty {
                ContentUnavailableView {
                    Label("No Source Selected", systemImage: Symbols.sources)
                } description: {
                    Text("Click a numbered citation in an answer to read the passage BOAR used.")
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(sources) { source in
                            SourceInspectorRow(source: source, technicalDetails: technicalDetails,
                                               expanded: expandedBinding(source))
                                .id(source.number)
                        }
                    }
                    .listStyle(.inset)
                    .alternatingRowBackgrounds(.disabled)
                    .onChange(of: selected) { _, source in
                        if let source { withAnimation { proxy.scrollTo(source.number, anchor: .top) } }
                    }
                }
            }
        }
    }

    private func expandedBinding(_ source: ChatSource) -> Binding<Bool> {
        Binding(get: { selected == source }, set: { selected = $0 ? source : nil })
    }
}

/// One source in the inspector: number and title, then (expanded) its passage, match and article link.
private struct SourceInspectorRow: View {
    let source: ChatSource
    let technicalDetails: Bool
    @Binding var expanded: Bool

    private var symbol: String { source.number <= 50 ? "\(source.number).circle.fill" : "number.circle.fill" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(source.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: symbol)
                            .foregroundStyle(.tint)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Source \(source.number): \(source.title)"))

            Text(source.body)
                .lineLimit(expanded ? nil : 3)
                .foregroundStyle(expanded ? .primary : .secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if expanded {
                HStack {
                    if technicalDetails, let sim = source.similarity {
                        Text("Match \(sim, format: .percent.precision(.fractionLength(0)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") { Platform.copy(source.body) }
                        .help("Copy the passage")
                    if let url = source.url {
                        Link(destination: url) {
                            Label("Open Article", systemImage: "safari")
                        }
                        .help("Opens the full article in your browser. Needs internet.")
                    }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }
}
#endif
