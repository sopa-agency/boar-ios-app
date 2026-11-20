import BoarAnswer
import BoarCore
import SwiftUI

/// Chats: automatic titles and how many saved chats to keep.
struct SettingsMemorySection: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    let bridge: SettingsBridge
    /// A limit under the chats there are waits behind a dialog naming the oldest (android rc3 e2530996): the limit picked
    /// and the chats it would delete, oldest first.
    @State private var lowering: Lowering?

    private struct Lowering {
        let max: Int
        let going: [ChatSession]
    }

    /// Reads the saved limit; a pick that would delete chats is held, not written.
    private var limit: Binding<Int> {
        Binding(
            get: { bridge.read { $0.maxSavedSessions } },
            set: { pick($0) }
        )
    }

    var body: some View {
        Section {
            Toggle(isOn: bridge.binding({ $0.autoGenerateTitles }, { $0.autoGenerateTitles = $1 })) {
                SettingsLabel("Generate Chat Titles", symbol: "character.cursor.ibeam")
            }
            Picker(selection: limit) {
                Text("All Chats").tag(AppSettings.keepAllChats)
                ForEach([5, 10, 25, 50], id: \.self) { Text(verbatim: "\($0)").tag($0) }
            } label: {
                SettingsLabel("Saved Chats to Keep", symbol: "tray.full.fill")
            }
            .pickerStyle(.menu)
            Toggle(isOn: bridge.binding({ $0.confirmChatDelete }, { $0.confirmChatDelete = $1 })) {
                SettingsLabel("Ask Before Deleting a Chat", symbol: "trash.fill")
            }
        } header: {
            BoarHeader {
                Text("Chats")
            }
        } footer: {
            BoarFooter {
                Text("New chats are named from your first message. BOAR keeps every chat unless you set a limit; then it asks before it deletes your oldest ones. Off, one tap deletes a chat.")
            }
        }
        .task {
            if let d = DebugLaunch.dialog, d.hasPrefix("lower-"), let n = Int(d.dropFirst(6)) {
                try? await Task.sleep(for: .seconds(1))
                pick(n)
            }
        }
        .alert("Delete your oldest chats?", isPresented: Binding(get: { lowering != nil }, set: { if !$0 { lowering = nil } }),
               presenting: lowering) { l in
            Button("Keep All Chats") {
                bridge.settings.maxSavedSessions = AppSettings.keepAllChats
                bridge.touch()
            }
            Button("Delete Them", role: .destructive) { deleteNow(l) }
            Button("Cancel", role: .cancel) {}
        } message: { l in
            Text(PruneText.of(Self.message(l.max, l.going), "", pluginsOn: false))
        }
    }

    private func pick(_ value: Int) {
        let going = (try? services.chats.pushedOutAt(maxSessions: value)) ?? []
        if going.isEmpty {
            bridge.settings.maxSavedSessions = value
            bridge.touch()
        } else {
            lowering = Lowering(max: value, going: going)
        }
    }

    /// Sets the limit and deletes now, as the chat's own prune does after an answer. The open chat, when it goes, becomes a
    /// new chat, as a deleted one does: opening an old chat doesn't make it newer.
    private func deleteNow(_ l: Lowering) {
        bridge.settings.maxSavedSessions = l.max
        bridge.touch()
        let max = l.max
        let going = Set(l.going.map(\.id))
        Task {
            _ = try? await services.background { try $0.chats.prune(maxSessions: max) }
            // As AppModel.deleteSession: Settings stays on screen; only a sidebar pointing at a deleted chat moves.
            if let open = model.chat?.sessionId, going.contains(open) { model.chat?.newChat() }
            if case .session(let id) = model.selection, going.contains(id) { model.selection = .newChat }
            model.reloadSessions()
        }
    }

    /// "Keeping 5 chats deletes “A” and 2 more."
    private static func message(_ max: Int, _ going: [ChatSession]) -> String {
        let title = going[0].title
        if going.count > 1 {
            return String(localized: "Keeping \(max) chats deletes “\(title)” and \(going.count - 1) more.")
        }
        return String(localized: "Keeping \(max) chats deletes “\(title)”.")
    }
}
