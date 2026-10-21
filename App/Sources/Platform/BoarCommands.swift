#if os(macOS)
import SwiftUI

/// The Mac menu bar: About in the app menu, New Chat in File, Find Chats in Edit, a Chat menu (stop, answer style,
/// Deep Research, rename, delete) and the library screens in View.
struct BoarCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var ready: Bool {
        if case .ready = model.phase { model.lock?.locked != true } else { false }
    }

    private var answering: Bool { model.chat?.isAnswering ?? false }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About BOAR") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Chat", action: model.newChat)
                .keyboardShortcut("n")
                .disabled(!ready || answering)
            Button("Import Documents…") {
                model.selection = .screen(.documents)
                model.importRequest = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!ready || model.documents?.busy == true)
        }

        CommandGroup(after: .textEditing) {
            Button("Find Chats…") { model.sidebarRequest = .find }
                .keyboardShortcut("f")
                .disabled(!ready)
        }

        CommandMenu("Chat") {
            Button("Stop Answering") { model.chat?.stop() }
                .keyboardShortcut(".")
                .disabled(!answering)
            Divider()
            if let chat = model.chat {
                Picker("Answer Style", selection: Binding(get: { chat.personalityId }, set: chat.setTone)) {
                    ForEach(chat.tones, id: \.id) { tone in
                        Text(tone.label).tag(tone.id)
                    }
                }
                Toggle("Deep Research", isOn: Binding(get: { chat.deepResearchEnabled }, set: chat.setDeepResearch))
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            Divider()
            Button("Rename Chat…") {
                if let id = model.selectedSessionId { model.sidebarRequest = .rename(id) }
            }
            .disabled(!ready || model.selectedSessionId == nil)
            Button("Delete Chat…") {
                if let id = model.selectedSessionId { model.sidebarRequest = .delete(id) }
            }
            .keyboardShortcut(.delete)
            .disabled(!ready || model.selectedSessionId == nil || answering)
        }

        // Like Messages' Window → Messages: brings the main window back after it was closed.
        CommandGroup(before: .windowList) {
            Button(String(localized: "BOAR", comment: "Window menu item that shows the main window")) { openWindow(id: "main") }
                .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(before: .sidebar) {
            Button("Chat") { model.selection = model.chat?.sessionId.map(SidebarItem.session) ?? .newChat }
                .keyboardShortcut("1")
                .disabled(!ready)
            ForEach(Array(AppScreen.sidebarCases.enumerated()), id: \.element) { index, screen in
                Button(screen.title) { model.selection = .screen(screen) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 2)")))
                    .disabled(!ready)
            }
            Divider()
        }
    }
}
#endif
