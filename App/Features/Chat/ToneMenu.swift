#if os(macOS)
import SwiftUI

/// The composer's style button on the Mac: a pop-up menu of the answer styles (each with what it does) and the Deep
/// Research switch, the same choices as the iPhone's style sheet.
struct ToneMenu: View {
    @Bindable var chat: ChatController
    let symbol: AppIcon

    var body: some View {
        Menu {
            Picker("How BOAR Answers", selection: Binding(get: { chat.personalityId }, set: chat.setTone)) {
                ForEach(chat.tones, id: \.id) { tone in
                    Button {
                    } label: {
                        Label {
                            Text(tone.displayLabel)
                            Text(ToneRow.detail(for: tone))
                        } icon: {
                            Image(icon: tone.symbol)
                        }
                    }
                    .tag(tone.id)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle(isOn: $chat.deepResearchEnabled) {
                Label {
                    Text("Deep Research")
                    Text("Splits your question into parts and researches each one. Slower.")
                } icon: {
                    Image(icon: Symbols.deepResearch)
                }
            }
        } label: {
            Label("Answer Style", icon: symbol)
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}
#endif
