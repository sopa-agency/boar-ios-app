import SwiftUI

/// Appearance (System / Light / Dark) and haptics.
struct SettingsDisplaySection: View {
    @Environment(AppModel.self) private var model
    let bridge: SettingsBridge

    var body: some View {
        @Bindable var model = model
        Section {
            Picker(selection: $model.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
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
            BoarHeader {
                Text("Display")
            }
        } footer: {
            BoarFooter {
                #if !os(macOS)
                Text("Text size follows your \(Platform.deviceNoun)'s Dynamic Type setting.")
                #endif
            }
        }
    }
}
