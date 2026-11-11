import BoarCore
import SwiftUI

/// The last section (android RecoverySection): the tour again, then the destructive actions: clear the chats, reset the
/// settings (setup opens again), erase everything.
struct SettingsRecoverySection: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    let bridge: SettingsBridge
    /// The tour's cover lives on the screen that holds this section, outside the List: a List can drop an offscreen
    /// row, and the cover on it (rotating to landscape moves this last row off screen).
    @Binding var touring: Bool
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var confirmPurge = false
    @State private var cleared = false
    @State private var purging = false

    private var answering: Bool { model.chat?.isAnswering ?? false }

    var body: some View {
        Section {
            // The tour on its own (android "See the tour"): Done comes back here.
            Button {
                touring = true
            } label: {
                Label("See the Tour", systemImage: "signpost.right")
                    .foregroundStyle(.boar(.link))
            }
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                // Android's LinkButton: danger until it's done, then the link color (SettingsScreen.kt ClearChats).
                Label(cleared ? "Chat History Cleared" : "Clear Chat History", icon: cleared ? Symbols.active : Symbols.delete)
                    .foregroundStyle(.boar(cleared ? .link : .danger))
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(cleared || answering)
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset Settings", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(.boar(.link))
            }
            Button(role: .destructive) {
                confirmPurge = true
            } label: {
                Label(purging ? "Erasing…" : "Erase All Data", systemImage: "xmark.bin")
                    .foregroundStyle(.boar(.danger))
            }
            .disabled(purging || answering)
        } footer: {
            BoarFooter {
                Text("Reset Settings and Erase All Data reopen setup.")
            }
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
            Labs.shared.eraseUserData()
            cleared = true
            model.reloadSessions()
            await model.chat?.refreshSettings()
        }
    }

    private func resetSettings() {
        services.settings.resetPreferences()
        services.backend = .llama
        model.themeWasReset()
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
            model.themeWasReset()
            model.reloadSessions()
            await model.chat?.refreshSettings()
            model.reopenSetup()
        }
    }
}
