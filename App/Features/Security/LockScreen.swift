import SwiftUI

/// Covers BOAR while the app lock is closed (android PinScreens.kt's unlock screen, with Face ID instead of a PIN pad).
struct LockScreen: View {
    let lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmErase = false
    /// Face ID is offered by itself once per lock (its own sheet makes the scene inactive and active again).
    @State private var autoPrompted = DebugLaunch.holdsLockScreen

    var body: some View {
        ContentUnavailableView {
            Label("BOAR is locked", icon: Symbols.lock)
        } description: {
            if lock.keyLost {
                Text("The key that opens your chats is gone (this \(Platform.deviceNoun)'s passcode was turned off). The chats can't be read any more.")
            } else {
                Text("Your saved chats are encrypted on this \(Platform.deviceNoun).")
            }
            if let error = lock.error {
                Text(error).foregroundStyle(.red)
            }
        } actions: {
            if lock.keyLost {
                Button("Erase Chats and Files and Turn Off the Lock", role: .destructive, action: askErase)
                    .buttonStyle(.boarProminent)
                    .disabled(lock.busy)
                    .confirmationDialog("Erase your chats and Personal Files?", isPresented: $confirmErase, titleVisibility: .visible) {
                        Button("Erase Chats and Files", role: .destructive, action: erase)
                    } message: {
                        Text("Every saved chat and your Personal Files are deleted, and the lock turns off. Models and knowledge packs stay.")
                    }
            } else {
                Button("Unlock with \(lock.methodName)", systemImage: lock.methodSymbol, action: unlock)
                    .buttonStyle(.boarProminent)
                    .controlSize(.large)
                    .disabled(lock.busy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task(id: scenePhase) {
            // Asks right away when BOAR comes to the front, as other locked apps do.
            guard scenePhase == .active, !autoPrompted, lock.locked, !lock.keyLost else { return }
            autoPrompted = true
            await lock.unlock()
        }
    }

    private func askErase() {
        confirmErase = true
    }

    private func erase() {
        Task { await lock.eraseChatsAndReset() }
    }

    private func unlock() {
        Task { await lock.unlock() }
    }
}
