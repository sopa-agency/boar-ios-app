import BoarCore
import SwiftUI

/// The step's one full-width button, pinned above the bottom safe area: the primary action, or a quieter one where the
/// page has its own (the guide's Not Now).
struct SetupBottomButton: View {
    let title: LocalizedStringKey
    var enabled = true
    var prominent = true
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        // A Mac assistant's button: its own width, at the trailing edge, Return presses the primary one.
        HStack {
            Spacer()
            styled(Button(action: action) {
                Text(title)
                    .frame(minWidth: 120)
            })
            .controlSize(.large)
            .keyboardShortcut(prominent ? .defaultAction : nil)
            .disabled(!enabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        #else
        // Android's PrimaryButton (the accent with inverse text, 14 pt corners) as the system's prominent glass button;
        // its SecondaryButton as plain glass.
        styled(Button(action: action) {
            Text(title)
                .boarText("ui.title")
                .frame(maxWidth: .infinity, minHeight: 22)
                .padding(.vertical, 8)
        })
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .disabled(!enabled)
        .padding()
        #endif
    }

    @ViewBuilder private func styled(_ button: some View) -> some View {
        if prominent {
            #if os(macOS)
            button.buttonStyle(.boarProminent)
            #else
            button.buttonStyle(.boarGlassProminent)
            #endif
        } else if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
