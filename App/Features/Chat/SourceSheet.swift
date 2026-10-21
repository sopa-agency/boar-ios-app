import SwiftUI

/// The exact passage a numbered source gave the model.
struct SourceSheet: View {
    let source: ChatSource
    let technicalDetails: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Passage") {
                    Text(source.body)
                        .textSelection(.enabled)
                }
                if technicalDetails {
                    Section {
                        if let sim = source.similarity {
                            LabeledContent("Match") {
                                Text(sim, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                            }
                        }
                        if let doc = source.docId, doc != source.title {
                            LabeledContent("Document", value: doc)
                        }
                    }
                }
                if let url = source.url {
                    Section {
                        Link(destination: url) {
                            Label("Open Full Article", systemImage: "safari")
                        }
                    } footer: {
                        Text("Opens in your browser. Needs internet.")
                    }
                }
            }
            .groupedListStyle()
            .navigationTitle(source.title)
            .navigationSubtitleIfAvailable(Text("Source \(source.number)"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton(action: close)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: "\(source.title)\n\n\(source.body)")
                }
            }
        }
        .macSheetSize(width: 520, height: 560)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func close() {
        dismiss()
    }
}
