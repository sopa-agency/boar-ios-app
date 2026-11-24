import BoarCore
import SwiftUI

/// Start over (android RecoverySection): run setup again, reset the settings (setup opens again), erase
/// everything. Clearing the chats lives with the chats.
struct SettingsRecoverySection: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    let bridge: SettingsBridge
    @State private var confirmReset = false
    @State private var confirmPurge = false
    @State private var purging = false

    private var answering: Bool { model.chat?.isAnswering ?? false }

    var body: some View {
        Section {
            Button(action: model.reopenSetup) {
                Label("Run Setup Again", icon: Symbols.retry)
                    .foregroundStyle(.boar(.link))
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
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
        } header: {
            BoarHeader {
                Text("Start Over")
            }
        } footer: {
            BoarFooter {
                Text("Run Setup Again checks your models and library. Reset Settings and Erase All Data reopen setup.")
            }
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

    private func resetSettings() {
        services.settings.resetPreferences()
        // BOAR's own avatar again; the avatars unlocked stay unlocked (android SettingsScreen).
        services.vault.equip(nil)
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
