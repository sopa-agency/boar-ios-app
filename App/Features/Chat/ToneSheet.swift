import BoarAnswer
import SwiftUI

/// The style sheet (android ToneSheet): every answer style with what it does, the current one checked, and Deep
/// Research below (it runs in any style). A choice applies at once.
struct ToneSheet: View {
    @Bindable var chat: ChatController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("How BOAR Answers") {
                    ForEach(chat.tones, id: \.id) { tone in
                        ToneRow(tone: tone, selected: tone.id == chat.personalityId, onSelect: select)
                    }
                }
                Section {
                    Toggle(isOn: $chat.deepResearchEnabled) {
                        Label("Deep Research", icon: Symbols.deepResearch)
                    }
                } footer: {
                    Text("Splits your question into parts and researches each one. Slower.")
                }
            }
            .groupedListStyle()
            .navigationTitle("Answer Style")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton(action: close)
                }
            }
        }
        .macSheetSize(width: 440, height: 520)
        .presentationDetents([.medium, .large])
    }

    private func select(_ id: String) {
        chat.setTone(id)
        dismiss()
    }

    private func close() {
        dismiss()
    }
}
