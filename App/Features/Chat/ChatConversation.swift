import SwiftUI

/// The messages, scrolled to the end as the answer streams.
struct ChatConversation: View {
    let chat: ChatController
    let onReuse: (String) -> Void
    let onOpenSource: (ChatSource) -> Void
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                LoadCrashNotice(chat: chat)
                ForEach(chat.messages) { message in
                    MessageRow(message: message, chat: chat, onReuse: onReuse, onOpenSource: onOpenSource)
                        .id(message.id)
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
