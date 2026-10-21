import BoarCore
import SwiftUI

/// The destructive actions, last on the page: clear the chats, reset the settings (setup opens again), erase everything.
struct SettingsRecoverySection: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    let bridge: SettingsBridge
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var confirmPurge = false
    @State private var cleared = false
    @State private var purging = false

    private var answering: Bool { model.chat?.isAnswering ?? false }

    var body: some View {
        Section {
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label(cleared ? "Chat History Cleared" : "Clear Chat History", systemImage: cleared ? "checkmark" : Symbols.delete)
                    .foregroundStyle(.red)
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(cleared || answering)
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset Settings", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(.red)
            }
            Button(role: .destructive) {
                confirmPurge = true
            } label: {
                Label(purging ? "Erasing…" : "Erase All Data", systemImage: "xmark.bin")
                    .foregroundStyle(.red)
            }
            .disabled(purging || answering)
        } footer: {
            Text("Reset Settings and Erase All Data reopen setup.")
        }
        .sensoryFeedback(.success, trigger: cleared) { _, new in new }
        .onAppear { cleared = false }
        .task(id: cleared) {
            guard cleared else { return }
            try? await Task.sleep(for: .seconds(2))
            cleared = false
        }
        .confirmationDialog("Clear all chat history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Chat History", role: .destructive, action: clearChats)
        } message: {
            Text("Every saved chat and message on this \(Platform.deviceNoun) is deleted. Models, documents and settings stay.")
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Settings", role: .destructive, action: resetSettings)
        } message: {
            Text("Settings go back to their defaults and setup opens again. Your models, packs, chats, documents and the lock are kept.")
        }
        .confirmationDialog("Erase all data?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Erase All Data", role: .destructive, action: erase)
        } message: {
            Text("This can't be undone. Every downloaded model, knowledge pack, document and chat is deleted, and setup starts over.")
        }
    }

    private func clearChats() {
        Task {
            _ = try? await services.background { try $0.chats.clearAll() }
            cleared = true
            model.reloadSessions()
            await model.chat?.refreshSettings()
        }
    }

    private func resetSettings() {
        services.settings.resetPreferences()
        services.backend = .llama
        model.appearance = .system
        bridge.touch()
        Task {
            await services.host.unload()
            await model.chat?.refreshSettings()
            model.reopenSetup()
        }
    }

    private func erase() {
        purging = true
        Task {
            await DataPurge.eraseAll(services: services, lock: model.lock)
            purging = false
            model.appearance = .system
            model.reloadSessions()
            await model.chat?.refreshSettings()
            model.reopenSetup()
        }
    }
}
