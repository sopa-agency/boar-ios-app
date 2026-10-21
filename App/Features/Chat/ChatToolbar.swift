import SwiftUI

/// The chat's toolbar: one action, a new chat.
struct ChatToolbar: ToolbarContent {
    let chat: ChatController
    let onNewChat: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("New Chat", systemImage: Symbols.newChat, action: onNewChat)
                .disabled(chat.isAnswering)
        }
    }
}
