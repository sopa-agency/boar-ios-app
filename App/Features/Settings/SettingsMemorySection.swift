import BoarCore
import SwiftUI

/// Chats: automatic titles and how many saved chats to keep.
struct SettingsMemorySection: View {
    let bridge: SettingsBridge

    var body: some View {
        Section {
            Toggle(isOn: bridge.binding({ $0.autoGenerateTitles }, { $0.autoGenerateTitles = $1 })) {
                SettingsLabel("Generate Chat Titles", symbol: "character.cursor.ibeam", color: .orange)
            }
            Picker(selection: bridge.binding({ $0.maxSavedSessions }, { $0.maxSavedSessions = $1 })) {
                ForEach([5, 10, 25, 50], id: \.self) { Text(verbatim: "\($0)").tag($0) }
            } label: {
                SettingsLabel("Saved Chats to Keep", symbol: "tray.full.fill", color: .brown)
            }
            .pickerStyle(.menu)
        } header: {
            Text("Chats")
        } footer: {
            Text("New chats are named from your first message. Older chats are removed past the limit.")
        }
    }
}
