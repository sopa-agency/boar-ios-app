import BoarCore
import SwiftUI

/// The step's one full-width primary button, pinned above the bottom safe area.
struct SetupBottomButton: View {
    let title: LocalizedStringKey
    var enabled = true
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        #if os(macOS)
        // A Mac assistant's button: its own width, at the trailing edge, Return presses it.
        HStack {
            Spacer()
            Button(action: action) {
                Text(title)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        #else
        // Android's PrimaryButton: the accent with inverse text, bgCard and dim text when disabled.
        Button(action: action) {
            Text(title)
                .boarText("ui.title")
                .foregroundStyle(Color(enabled ? palette.textInverse : palette.textDim))
                .frame(maxWidth: .infinity, minHeight: 22)
                .padding(.vertical, 15)
                .background(Color(enabled ? palette.emerald500 : palette.bgCard), in: .rect(cornerRadius: 14))
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding()
        #endif
    }
}
