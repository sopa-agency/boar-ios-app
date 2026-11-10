import SwiftUI

/// Privacy: lock BOAR (and encrypt the chats) with Face ID, Touch ID or the passcode.
struct SettingsSecuritySection: View {
    @Bindable var lock: AppLock

    var body: some View {
        let canLock = lock.available || lock.enabled
        Section {
            Toggle(isOn: $lock.enabledChoice) {
                SettingsLabel("Lock with \(lock.methodName)", symbol: Symbols.lock)
            }
                .disabled(lock.busy || !canLock)
        } header: {
            BoarHeader {
                Text("Privacy")
            }
        } footer: {
            BoarFooter {
                VStack(alignment: .leading) {
                    if !canLock {
                        Text("Set a passcode for your \(Platform.deviceNoun) in the Settings app to lock BOAR.")
                    } else if lock.enabled {
                        Text("Chats are encrypted and open only after \(lock.methodName).")
                    } else {
                        Text("Anyone who can open your \(Platform.deviceNoun) can read your chats in BOAR.")
                    }
                    if let error = lock.error {
                        Text(error).foregroundStyle(.boar(.danger))
                    }
                }
            }
        }
    }
}
