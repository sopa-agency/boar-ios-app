import BoarCore
import SwiftUI

/// The step's one full-width primary button, pinned above the bottom safe area.
struct SetupBottomButton: View {
    let title: LocalizedStringKey
    var enabled = true
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        // A Mac assistant's button: its own width, at the trailing edge, Return presses it.
        HStack {
            Spacer()
            Button(action: action) {
                Text(title)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.boarProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        #else
        // Android's PrimaryButton (the accent with inverse text, 14 pt corners) as the system's prominent glass button.
        Button(action: action) {
            Text(title)
                .boarText("ui.title")
                .frame(maxWidth: .infinity, minHeight: 22)
                .padding(.vertical, 8)
        }
        .buttonStyle(.boarGlassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .disabled(!enabled)
        .padding()
        #endif
    }
}
