import BoarAnswer
import SwiftUI

/// The drawer (Drawer.tsx) as a sidebar: recent chats (open, rename, delete) and the library (Documents, Models). Settings
/// and New Chat share the one compact top bar.
struct SessionsSidebar: View {
    @Environment(AppModel.self) private var model
    let chat: ChatController
    @State private var renaming: ChatSession?
    @State private var deleting: ChatSession?
    @State private var newTitle = ""
    @State private var query = ""
    @FocusState private var searching: Bool

    /// The chats whose title matches the sidebar search (all of them with no search).
    private var shownSessions: [ChatSession] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.sessions }
        return model.sessions.filter { $0.title.localizedStandardContains(q) }
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                ForEach(AppScreen.sidebarCases) { screen in
                    Label(screen.title, systemImage: screen.symbol)
                        .tag(SidebarItem.screen(screen))
                }
                // Android's drawer entry: only while Boar Labs is on (Settings → Advanced).
                if Labs.shared.labsOn {
                    Label(AppScreen.labs.title, systemImage: AppScreen.labs.symbol)
                        .tag(SidebarItem.screen(.labs))
                }
            }

            Section {
                if model.sessions.isEmpty {
                    Text("Your chats appear here.")
                        .foregroundStyle(.secondary)
                } else if shownSessions.isEmpty {
                    Text("No chats match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shownSessions) { session in
                    SessionRow(session: session)
                        .tag(SidebarItem.session(session.id))
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: Symbols.delete, role: .destructive) { askDelete(session) }
                                .disabled(isAnswering(in: session))
                            Button("Rename", systemImage: "pencil") { startRename(session) }
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { startRename(session) }
                            Button("Delete", systemImage: Symbols.delete, role: .destructive) { askDelete(session) }
                                .disabled(isAnswering(in: session))
                        }
                }
            } header: {
                Text("Chats")
            } footer: {
                Label("Works without internet", systemImage: Symbols.offline)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Text(verbatim: "BOAR"))
        // One compact bar: Settings on the left, New Chat on the right, the title between them. No large title row
        // and no bottom bar holding a lone button.
        .inlineNavigationTitle()
        .toolbar {
            #if !os(macOS)
            // The Mac has Settings in the app menu (⌘,).
            ToolbarItem(placement: .leadingBar) {
                Button("Settings", systemImage: AppScreen.settings.symbol, action: openSettings)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("New Chat", systemImage: Symbols.newChat, action: model.newChat)
                    .disabled(chat.isAnswering)
                    .help("New Chat (⌘N)")
            }
        }
        .refreshable { model.reloadSessions() }
        #if os(macOS)
        .searchable(text: $query, placement: .sidebar, prompt: Text("Search Chats"))
        .searchFocused($searching)
        // The Delete key on a selected chat, and the Chat menu's Rename / Delete / Find commands.
        .onDeleteCommand {
            if let id = model.selectedSessionId, let session = model.sessions.first(where: { $0.id == id }),
               !isAnswering(in: session) { askDelete(session) }
        }
        .onChange(of: model.sidebarRequest) { _, request in handle(request) }
        #endif
        .alert("Rename Chat", item: $renaming) { session in
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename(session) }
        }
        .confirmationDialog("Delete this chat?", item: $deleting, titleVisibility: .visible) { session in
            Button("Delete", role: .destructive) { delete(session) }
        } message: { session in
            Text("\"\(session.title)\" and its messages are deleted from this \(Platform.deviceNoun).")
        }
    }

    #if os(macOS)
    private func handle(_ request: SidebarRequest?) {
        guard let request else { return }
        model.sidebarRequest = nil
        switch request {
        case .find: searching = true
        case .rename(let id): if let s = model.sessions.first(where: { $0.id == id }) { startRename(s) }
        case .delete(let id): if let s = model.sessions.first(where: { $0.id == id }) { askDelete(s) }
        }
    }
    #endif

    private func openSettings() {
        model.selection = .screen(.settings)
    }

    private func isAnswering(in session: ChatSession) -> Bool {
        chat.isAnswering && chat.sessionId == session.id
    }

    private func startRename(_ session: ChatSession) {
        newTitle = session.title
        renaming = session
    }

    private func rename(_ session: ChatSession) {
        let title = newTitle
        Task { await model.renameSession(session.id, to: title) }
    }

    /// Settings → Ask before deleting a chat: on, the dialog naming the chat; off, one tap deletes it.
    private func askDelete(_ session: ChatSession) {
        if chat.services.settings.confirmChatDelete { deleting = session } else { delete(session) }
    }

    private func delete(_ session: ChatSession) {
        Task { await model.deleteSession(session.id) }
    }
}
