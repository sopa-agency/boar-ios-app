import BoarAnswer
import SwiftUI

/// Under a finished answer (android Bubble's footer, adam Nov 14): a thin separator, then BOAR's notes about it (the style
/// it kept, the number check, no source) and the plugins' after them, oldest first; then one row with the receipt (time and
/// speed) at the start and the buttons at the end: copy, and More (Ask Again; Performance Details with technical details
/// on; the switched-on labs' actions, android's 🧩 sheet). The rating (android's ▲ ▼) is hidden as on Android, which
/// keeps its code for when something uses ratings.
struct AnswerFooter: View {
    let message: ChatItem
    let chat: ChatController
    let shown: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var showingReceipt = false

    /// android `SHOW_RATING`: nothing uses ratings yet (adam, Nov 11).
    private static let showRating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color(palette.borderSubtle))
                .frame(height: 0.5)
                .padding(.top, 8)
            notes
            HStack {
                if Self.showRating {
                    rateButton("up", "Good Answer", symbol: "hand.thumbsup", on: .success)
                    rateButton("down", "Bad Answer", symbol: "hand.thumbsdown", on: .danger)
                }
                // The receipt on the left, filling the row up to the buttons.
                Group {
                    if let receipt = message.receipt {
                        ReceiptButton(receipt: receipt, opens: chat.technicalDetails, action: showReceipt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy", systemImage: "doc.on.doc", action: copy)
                moreMenu
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingReceipt) {
            if let receipt = message.receipt { ReceiptDetails(receipt: receipt) }
        }
        .debugReceipt($showingReceipt)
    }

    /// BOAR's notes first, then the plugins' (android: a plugin's error goes after BOAR's own, the newest last).
    @ViewBuilder private var notes: some View {
        // Answered in another style than the one picked (a health question under Detailed): said once.
        if let note = message.receipt?.styleNote {
            switch note {
            case "health": MessageNote(symbol: Symbols.shortAnswer, text: "Short answer: health questions are kept brief.", warning: false)
            case "seed": MessageNote(symbol: Symbols.shortAnswer, text: "Short answer: seed-phrase questions are kept brief, for your safety.", warning: false)
            default: EmptyView()
            }
        }
        // Every number written is in a source (or is not), once the staged answer's check has run.
        if !message.sources.isEmpty, let staged = message.staged {
            StagedCheck(staged: staged)
        }
        // Nothing in the library backs it: said, not left to guess (t9 0226 point 4).
        if NoSource.shows(searched: message.receipt?.retrievalMs != nil, sources: message.sources.count, instant: message.receipt?.tool != nil,
                          question: chat.question(for: message.id) ?? "", answer: message.text, style: message.receipt?.style) {
            MessageNote(symbol: Symbols.shortAnswer, text: "No source in this \(Platform.deviceNoun)'s library covers this; the answer is from the model alone.", warning: false)
        }
        ForEach(Labs.shared.answerNotes(answerRef)) { note in
            Text(verbatim: note.text)
                .font(.footnote)
                .foregroundStyle(note.error ? .boar(.danger) : .boar(.muted))
        }
    }

    /// The rating, tapped again to take it back; filled and in its color while set.
    private func rateButton(_ rating: String, _ title: LocalizedStringKey, symbol: String, on role: BoarStyle.Role) -> some View {
        let set = message.feedback == rating
        return Button(title, systemImage: set ? symbol + ".fill" : symbol) { chat.rate(message.id, rating) }
            .foregroundStyle(set ? AnyShapeStyle(BoarStyle(role: role)) : AnyShapeStyle(.secondary))
            .accessibilityAddTraits(set ? .isSelected : [])
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Ask Again", icon: Symbols.retry, action: askAgain)
                .disabled(chat.isAnswering)
            if chat.technicalDetails, message.receipt != nil {
                Button("Performance Details", icon: Symbols.performance, action: showReceipt)
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
