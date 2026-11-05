import SwiftUI

/// Under a finished answer: copy, and More (Ask Again; Performance Details with technical details on; the switched-on
/// labs' actions, android's 🧩 sheet).
struct AnswerFooter: View {
    let message: ChatItem
    let chat: ChatController
    let shown: String
    @Environment(AppModel.self) private var model
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
            let actions = Labs.shared.answerActions(answerRef)
            if !actions.isEmpty {
                Section {
                    ForEach(actions) { action in
                        Button(action.title, systemImage: action.done ? "checkmark.circle.fill" : action.systemImage) { action.run() }
                    }
                }
            }
        }
        .labelStyle(.iconOnly)
    }

    /// This answer as the lab slots see it.
    private var answerRef: AnswerRef {
        let session = chat.sessionId.flatMap { id in model.sessions.first { $0.id == id } }
        let speed = message.receipt?.tokPerSec ?? 0
        return AnswerRef(id: message.id, sessionId: chat.sessionId, chatTitle: session?.title ?? "",
                         question: chat.question(for: message.id) ?? "", text: shown,
                         sources: message.sources.map { ($0.title, $0.source) }, model: message.receipt?.model,
                         tokPerSec: speed > 0 ? speed : nil)
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
