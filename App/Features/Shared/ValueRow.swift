import SwiftUI

/// A form row with a value on the right, selectable for copying (telemetry, About): the key in ui.subtext muted and
/// the value in mono.xs, as Android's device info rows (SettingsScreen.kt).
struct ValueRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent {
            Text(verbatim: value)
                .boarText("mono.xs")
                .foregroundStyle(.boar(.primary))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(label)
                .font(.boar("ui.subtext"))
                .foregroundStyle(.boar(.muted))
        }
    }
}
