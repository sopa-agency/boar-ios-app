import BoarCore
import SwiftUI

/// Chats: automatic titles and how many saved chats to keep.
struct SettingsMemorySection: View {
    let bridge: SettingsBridge

    var body: some View {
        Section {
            Toggle(isOn: bridge.binding({ $0.autoGenerateTitles }, { $0.autoGenerateTitles = $1 })) {
                SettingsLabel("Generate Chat Titles", symbol: "character.cursor.ibeam")
            }
            Picker(selection: bridge.binding({ $0.maxSavedSessions }, { $0.maxSavedSessions = $1 })) {
                ForEach([5, 10, 25, 50], id: \.self) { Text(verbatim: "\($0)").tag($0) }
            } label: {
                SettingsLabel("Saved Chats to Keep", symbol: "tray.full.fill")
            }
            .pickerStyle(.menu)
            Toggle(isOn: bridge.binding({ $0.confirmChatDelete }, { $0.confirmChatDelete = $1 })) {
                SettingsLabel("Ask Before Deleting a Chat", symbol: "trash.fill")
            }
        } header: {
            Text("Chats")
        } footer: {
            BoarFooter {
                Text("New chats are named from your first message. Older chats are removed past the limit. Off, one tap deletes a chat.")
            }
        }
    }
}
