import SwiftUI

/// Sessions sidebar → chat (or another screen). On iPhone it opens on the chat; the sidebar is one back-swipe away.
struct MainSplitView: View {
    @Environment(AppModel.self) private var model
    let chat: ChatController
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            SessionsSidebar(chat: chat)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
                #else
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                #endif
        } detail: {
            NavigationStack {
                switch model.selection {
                case .screen(let screen):
                    DestinationScreen(screen: screen)
                case .newChat, .session, .none:
                    ChatView(chat: chat)
                }
            }
        }
        .onChange(of: model.selection) { _, item in model.select(item) }
        .debugSidebar($compactColumn)
    }
}
