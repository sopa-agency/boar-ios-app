import SwiftUI

/// The messages, scrolled to the end as the answer streams.
struct ChatConversation: View {
    let chat: ChatController
    let onReuse: (String) -> Void
    let onOpenSource: (ChatSource) -> Void
    /// The field has text: the Keep going bubbles step aside.
    var typing = false
    var onAsk: (String) -> Void = { _ in }
    var onFill: (String) -> Void = { _ in }
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                LoadCrashNotice(chat: chat)
                ForEach(chat.messages) { message in
                    MessageRow(message: message, chat: chat, onReuse: onReuse, onOpenSource: onOpenSource)
                        .id(message.id)
                }
                // "Keep going" under the latest answer, outside its card, on the user's side (t9 0235): not while BOAR answers or
                // questions wait, gone when the field has text or a newer answer arrives, and not under a load note or the
                // keep-chats note either: keepGoing refuses then, so a tap did nothing (validator A-3).
                if let last = chat.messages.last, !last.isUser, !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !chat.isAnswering, chat.queued.isEmpty, !typing, !chat.noteUp, chat.pruneNote == nil {
                    KeepGoingGroup(last: last, question: chat.question(for: last.id) ?? "", onStep: { chat.keepGoing(last.id, $0) },
                                   onAsk: onAsk, onFill: onFill)
                        .id("keep-going-" + last.id)
                }
                if let error = chat.error {
                    Label {
                        Text(error)
                    } icon: {
                        Image(icon: Symbols.error).foregroundStyle(.red)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        #if os(macOS)
        // A crisp edge under the title bar: the answer text doesn't blur into the window title.
        .scrollEdgeEffectStyle(.hard, for: .top)
        #endif
        // Keeps the end of the streaming answer in view unless the reader scrolled up.
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: chat.messages.count) {
            withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
        }
    }
}
