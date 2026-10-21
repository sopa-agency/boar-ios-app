import SwiftUI

/// Under a finished answer: copy, and More (Ask Again; Performance Details with technical details on).
struct AnswerFooter: View {
    let message: ChatItem
    let chat: ChatController
    let shown: String
    @State private var showingReceipt = false

    var body: some View {
        HStack {
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            Spacer(minLength: 0)
            if chat.technicalDetails, let receipt = message.receipt {
                ReceiptButton(receipt: receipt, action: showReceipt)
            }
            moreMenu
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .sheet(isPresented: $showingReceipt) {
            if let receipt = message.receipt { ReceiptDetails(receipt: receipt) }
        }
        .debugReceipt($showingReceipt)
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Ask Again", systemImage: Symbols.retry, action: askAgain)
                .disabled(chat.isAnswering)
            if chat.technicalDetails, message.receipt != nil {
                Button("Performance Details", systemImage: Symbols.performance, action: showReceipt)
            }
        }
        .labelStyle(.iconOnly)
    }

    private func askAgain() {
        if let q = chat.question(for: message.id) { chat.send(q) }
    }

    private func showReceipt() {
        showingReceipt = true
    }

    private func copy() {
        Platform.copy(shown)
    }
}
