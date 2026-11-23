import SwiftUI

/// A tap on a source, a quote or an [n] (android 5c0f04fe, adam Nov 12): the article opens at the passage that backs the
/// answer, marked and scrolled into view (`SourceReader`), with no passage sheet in between. The chat stays under the
/// sheet, so closing it returns to the same place in the answer. A source stored without its document id (older answers)
/// has no article to open: it shows the passage itself.
struct SourceSheet: View {
    let source: ChatSource
    let technicalDetails: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(source.title)
                .navigationSubtitleIfAvailable(Text("Source \(source.number)"))
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton(action: close)
                    }
                    if let url = source.url {
                        // Opens in the browser: needs internet.
                        ToolbarItem(placement: .primaryAction) { Link(destination: url) { Label("Open Full Article", systemImage: "safari") } }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: "\(source.title)\n\n\(source.body)")
                    }
                }
        }
        .macSheetSize(width: 520, height: 560)
        // A whole article doesn't fit the half sheet.
        .presentationDetents(source.docId != nil ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var content: some View {
        if source.docId != nil {
            SourceReader(source: source)
        } else {
            List {
                Section("Passage") {
                    Text(source.body)
                        .textSelection(.enabled)
                }
                if technicalDetails, let sim = source.similarity {
                    Section {
                        LabeledContent("Match") {
                            Text(sim, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                        }
                    }
                }
            }
            .groupedListStyle()
        }
    }

    private func close() {
        dismiss()
    }
}
