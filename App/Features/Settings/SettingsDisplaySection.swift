import BoarCore
import SwiftUI

/// The theme (System, Campfire, Moonlight; Android's picker plus System) and haptics.
struct SettingsDisplaySection: View {
    @Environment(AppModel.self) private var model
    let bridge: SettingsBridge

    var body: some View {
        @Bindable var model = model
        Section {
            Picker(selection: $model.theme) {
                ForEach(ThemeChoice.choices(current: model.theme)) { choice in
                    choice.title.tag(choice)
                }
            } label: {
                SettingsLabel("Theme", symbol: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
            #if !os(macOS)
            Toggle(isOn: bridge.binding({ $0.hapticsEnabled }, { $0.hapticsEnabled = $1 })) {
                SettingsLabel("Haptics", symbol: "hand.tap.fill")
            }
            #endif
        } header: {
            Text("Display")
        } footer: {
            BoarFooter {
                Text("System follows your \(Platform.deviceNoun)'s appearance: Moonlight when dark, Paper when light.")
                #if !os(macOS)
                Text("Text size follows your \(Platform.deviceNoun)'s Dynamic Type setting.")
                #endif
            }
        }
    }
}
