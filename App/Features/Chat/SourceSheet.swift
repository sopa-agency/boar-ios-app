import SwiftUI

/// The exact passage a numbered source gave the model.
struct SourceSheet: View {
    let source: ChatSource
    let technicalDetails: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var reading = false
    /// The reader opens the sheet to full height: a whole article doesn't fit the half sheet.
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            List {
                Section("Passage") {
                    Text(source.body)
                        .textSelection(.enabled)
                }
                // The whole article or file, read on the phone; a source stored without its document id (older answers)
                // has none.
                if source.docId != nil {
                    Section {
                        Button {
                            reading = true
                        } label: {
                            Label("Read the Whole Article", systemImage: "doc.text")
                        }
                    } footer: {
                        Text("From this device, with the part BOAR used marked.")
                    }
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
            .navigationDestination(isPresented: $reading) { SourceReader(source: source) }
            .onChange(of: reading) { _, open in if open { detent = .large } }
            #if DEBUG
            .task { if DebugLaunch.isScreen("source-reader") { reading = true } }
            #endif
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private func close() {
        dismiss()
    }
}
