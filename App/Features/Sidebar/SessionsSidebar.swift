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
    /// A chat deleted a moment ago: hidden, deleted for real after `ChatList.undoMs` unless Undo is tapped (android
    /// ChatList.UNDO_MS).
    @State private var pendingDelete: ChatSession?
    @State private var undoTask: Task<Void, Never>?

    /// The saved chats without the one waiting for its Undo.
    private var kept: [ChatSession] { model.sessions.filter { $0.id != pendingDelete?.id } }

    /// The Mac's Find command (⌘F) asked for the search box: it shows then even with few chats.
    @State private var findAsked = false

    /// The search box shows above `ChatList.searchFrom` chats, on every platform (android ChatList), or after Find.
    private var searchable: Bool { kept.count > ChatList.searchFrom || findAsked }

    /// The chats whose title matches the sidebar search (all of them with no search).
    private var shownSessions: [ChatSession] {
        guard searchable else { return kept }
        return kept.filter { ChatList.matches(query, title: $0.title) }
    }

    /// Today, Yesterday, Earlier: the non-empty groups, newest first within each (android groupOf, by the calendar day).
    private var groups: [(group: ChatList.Group, sessions: [ChatSession])] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return ChatList.Group.allCases.compactMap { group in
            let rows = shownSessions.filter { ChatList.groupOf(updatedAt: $0.updatedAt, now: now) == group }
            return rows.isEmpty ? nil : (group, rows)
        }
    }

    private func title(_ group: ChatList.Group) -> LocalizedStringKey {
        switch group {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .earlier: "Earlier"
        }
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                ForEach(AppScreen.sidebarCases) { screen in
                    Label(screen.title, icon: screen.symbol)
                        .tag(SidebarItem.screen(screen))
                }
                // Android's drawer entry: only while Boar Labs is on (Settings → Advanced).
                if Labs.shared.labsOn {
                    Label(AppScreen.labs.title, icon: AppScreen.labs.symbol)
                        .tag(SidebarItem.screen(.labs))
                }
            }

            if searchable {
                Section {
                    TextField("Search Chats", text: $query)
                        .focused($searching)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search Chats")
                }
            }
            if groups.isEmpty {
                Section {
                    if kept.isEmpty {
                        Text("Your chats appear here.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No chats match.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Chats")
                } footer: {
                    Label("Works without internet", icon: Symbols.offline)
                }
            }
            ForEach(groups, id: \.group) { entry in
                Section {
                    ForEach(entry.sessions) { session in
                        row(session)
                    }
                } header: {
                    Text(title(entry.group))
                } footer: {
                    if entry.group == groups.last?.group {
                        Label("Works without internet", icon: Symbols.offline)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Android's drawer footer: the bars stay at the bottom while the chats scroll.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let pendingDelete {
                    UndoBar(title: pendingDelete.title, onUndo: undo)
                }
                if chat.technicalDetails {
                    SidebarStats(services: chat.services, lastTokPerSec: chat.isAnswering ? nil : chat.liveTokPerSec)
                        .background(.bar)
                }
            }
        }
        // Leaving the list ends the wait: the chat is deleted now, not left hidden.
        .onDisappear { commitDelete() }
        .navigationTitle(Text(verbatim: "BOAR"))
        // One compact bar: Settings on the left, New Chat on the right, the title between them. No large title row
        // and no bottom bar holding a lone button.
        .inlineNavigationTitle()
        .toolbar {
            #if !os(macOS)
            // The Mac has Settings in the app menu (⌘,).
            ToolbarItem(placement: .leadingBar) {
                Button("Settings", icon: AppScreen.settings.symbol, action: openSettings)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button("New Chat", icon: Symbols.newChat, action: model.newChat)
                    .disabled(chat.isAnswering)
                    .help("New Chat (⌘N)")
            }
        }
        .refreshable { model.reloadSessions() }
        #if os(macOS)
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
    }

    /// One chat's row: a tap opens it; a swipe or a long press has Rename and Delete (android ChatList's long-press menu; its
    /// "Add to Press" has no counterpart here, Press is BOAR-55).
    private func row(_ session: ChatSession) -> some View {
        SessionRow(session: session)
            .tag(SidebarItem.session(session.id))
            // A swipe and then a tap on its Delete are already deliberate: no dialog after them (Biel, BOAR-58). No full
            // swipe, which would delete on one long drag. Android's one-tap trash icon is what "Ask Before Deleting a
            // Chat" guards; here it guards the context menu and the Mac's Delete key. Every delete waits for Undo.
            // The chat BOAR is answering can't be deleted (android BoarDrawer). A swipe action doesn't look disabled, so it is
            // left out rather than shown red and dead (Biel, iPhone test 2026-11-24).
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !isAnswering(in: session) {
                    Button("Delete", icon: Symbols.delete, role: .destructive) { delete(session) }
                }
                Button("Rename", systemImage: "pencil") { startRename(session) }
            }
            .contextMenu {
                Button("Rename", systemImage: "pencil") { startRename(session) }
                Button("Delete", icon: Symbols.delete, role: .destructive) { askDelete(session) }
                    .disabled(isAnswering(in: session))
            }
            // On the row, not the list: on iPhone the dialog is a popover whose arrow points at what it is attached to.
            .confirmationDialog("Delete this chat?", isPresented: deleteAsked(session), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete(session) }
            } message: {
                Text("\"\(session.title)\" and its messages are deleted from this \(Platform.deviceNoun).")
            }
    }

    private func deleteAsked(_ session: ChatSession) -> Binding<Bool> {
        Binding(get: { deleting?.id == session.id }, set: { if !$0, deleting?.id == session.id { deleting = nil } })
    }

    #if os(macOS)
    private func handle(_ request: SidebarRequest?) {
        guard let request else { return }
        model.sidebarRequest = nil
        switch request {
        case .find:
            findAsked = true
            // The field may only appear now: focus it on the next turn, once it's in the list.
            Task { @MainActor in searching = true }
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

    /// Hides the chat and shows "Deleted: title · Undo"; after `ChatList.undoMs` it is deleted for real (android ChatList).
    /// A second delete settles the first at once.
    private func delete(_ session: ChatSession) {
        guard chat.leaveForDelete(session.id) else { return }
        commitDelete()
        if model.selection == .session(session.id) { model.selection = .newChat }
        withAnimation { pendingDelete = session }
        undoTask = Task {
            try? await Task.sleep(for: .milliseconds(ChatList.undoMs))
            guard !Task.isCancelled else { return }
            commitDelete()
        }
    }

    private func undo() {
        undoTask?.cancel()
        undoTask = nil
        withAnimation { pendingDelete = nil }
    }

    private func commitDelete() {
        undoTask?.cancel()
        undoTask = nil
        guard let session = pendingDelete else { return }
        pendingDelete = nil
        Task { await model.deleteSession(session.id) }
    }
}

/// "Deleted: title · Undo", under the list for `ChatList.undoMs`.
private struct UndoBar: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text("Deleted: \(title)")
                .lineLimit(1)
            Spacer()
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
