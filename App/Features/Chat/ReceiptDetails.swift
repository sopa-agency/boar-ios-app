import SwiftUI

/// main's receiptDetails: what the answer took, step by step (technical details on).
struct ReceiptDetails: View {
    let receipt: Receipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let model = receipt.model { ReceiptRow(label: "Model", symbol: Symbols.model, value: model) }
                    if let tool = receipt.tool { ReceiptRow(label: "Tool", symbol: "flask", value: tool) }
                    ReceiptRow(label: "Total", symbol: "clock", value: Receipt.seconds(receipt.totalMs))
                    ReceiptRow(label: "Time to first word", symbol: "timer", value: Receipt.seconds(receipt.ttftMs))
                    ReceiptRow(label: "Speed", symbol: Symbols.performance,
                               value: String(localized: "\(Receipt.rate(receipt.tokPerSec)) tok/s (~\(Receipt.words(receipt.tokPerSec)) words/s)"))
                }
                Section("Steps") {
                    if let load = receipt.loadMs { ReceiptRow(label: "Loading the model", symbol: "hourglass", value: Receipt.seconds(load)) }
                    if let search = receipt.retrievalMs { ReceiptRow(label: "Searching", symbol: "magnifyingglass", value: Receipt.seconds(search)) }
                    if let prefill = receipt.prefillMs { ReceiptRow(label: "Reading sources", symbol: Symbols.sources, value: Receipt.seconds(prefill)) }
                    if let context = receipt.contextTokens { ReceiptRow(label: "Text read", symbol: "doc.text", value: tokenCount(context)) }
                    ReceiptRow(label: "Words written", symbol: "pencil.line", value: tokenCount(receipt.tokens))
                }
            }
            .groupedListStyle()
            .navigationTitle("Performance Details")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton(action: close)
                }
            }
        }
        .macSheetSize(width: 460, height: 400)
        .presentationDetents([.medium, .large])
    }

    private func tokenCount(_ tokens: Int) -> String {
        String(localized: "~\(Receipt.words(Double(tokens))) words (\(tokens) tokens)")
    }

    private func close() {
        dismiss()
    }
}
