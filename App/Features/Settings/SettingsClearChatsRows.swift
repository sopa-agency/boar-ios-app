import BoarCore
import SwiftUI

/// Clear Chat History (android SettingsScreen ClearChats, in the chats section since profiles): deletes every saved chat,
/// keeps models, documents and settings; the Press basket only when asked.
struct SettingsClearChatsRows: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var confirmClear = false
    @State private var cleared = false

    private var answering: Bool { model.chat?.isAnswering ?? false }

    var body: some View {
        Button(role: .destructive) {
            confirmClear = true
        } label: {
            // Android's LinkButton: danger until it's done, then the link color (SettingsScreen.kt ClearChats).
            Label(cleared ? "Chat History Cleared" : "Clear Chat History", icon: cleared ? Symbols.active : Symbols.delete)
                .foregroundStyle(.boar(cleared ? .link : .danger))
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(cleared || answering)
        .sensoryFeedback(.success, trigger: cleared) { _, new in new }
        .onAppear { cleared = false }
        .task {
            if DebugLaunch.dialog == "clear-history" {
                try? await Task.sleep(for: .seconds(1))
                confirmClear = true
            }
        }
        .task(id: cleared) {
            guard cleared else { return }
            try? await Task.sleep(for: .seconds(2))
            cleared = false
        }
        .confirmationDialog("Clear all chat history?", isPresented: $confirmClear, titleVisibility: .visible) {
            // Press holds answers the user collected: kept unless they choose to delete it too (android: off by default).
            Button("Clear Chat History", role: .destructive) { clearChats(alsoPress: false) }
            if UserDataScope.offersPressChoice(pressItems: pressItems) {
                Button("Clear and Also Delete Press Projects (\(pressItems))", role: .destructive) { clearChats(alsoPress: true) }
            }
        } message: {
            Text("Every saved chat and message on this \(Platform.deviceNoun) is deleted. Models, documents and settings stay.")
        }
    }

    /// 0 hides the choice (android: no Press projects, no choice).
    private var pressItems: Int { Labs.shared.pressItems }

    private func clearChats(alsoPress: Bool) {
        Task {
            _ = try? await services.background { try $0.chats.clearAll() }
            // Press goes only when asked: an unreadable count keeps it too (android rc3 3f15cccd, R-A6).
            Labs.shared.eraseUserData(.clearHistory(alsoPress: alsoPress))
            cleared = true
            model.reloadSessions()
            await model.chat?.refreshSettings()
        }
    }
}
