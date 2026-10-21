import SwiftUI

/// One message: the user's question as a tinted bubble on the right, the answer as plain text on the left.
struct MessageRow: View {
    let message: ChatItem
    let chat: ChatController
    let onReuse: (String) -> Void
    let onOpenSource: (ChatSource) -> Void

    var body: some View {
        if message.isUser {
            UserBubble(text: message.text, onReuse: onReuse)
        } else {
            AnswerView(message: message, chat: chat, onOpenSource: onOpenSource)
        }
    }
}
