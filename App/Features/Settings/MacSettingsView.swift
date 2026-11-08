#if os(macOS)
import SwiftUI

/// The Mac's Settings window (⌘,): the iPhone's Settings page split into General, Privacy and Advanced tabs, each a
/// grouped form in the theme (`BoarForm`'s cards, text colors and fonts). Changes reach the open chat at once.
struct MacSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.lock?.locked == true {
            ContentUnavailableView("BOAR is locked", systemImage: "lock.fill",
                                   description: Text("Unlock BOAR in its window to change settings."))
                .frame(width: 420, height: 240)
        } else if let services = model.services {
            MacSettingsTabs(services: services)
        } else {
            ProgressView("Opening BOAR")
                .frame(width: 420, height: 240)
        }
    }
}

private struct MacSettingsTabs: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var bridge: SettingsBridge

    init(services: BoarServices) {
        self.services = services
        _bridge = State(initialValue: SettingsBridge(settings: services.settings))
    }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                BoarForm {
                    SettingsToneSection(services: services, bridge: bridge)
                    SettingsMemorySection(bridge: bridge)
                    SettingsDisplaySection(bridge: bridge)
                    SettingsVoiceSection(bridge: bridge)
                }
                .formStyle(.grouped)
                .frame(width: 600, height: 620)
            }
            Tab("Privacy", systemImage: "hand.raised") {
                BoarForm {
                    if let lock = model.lock { SettingsSecuritySection(lock: lock) }
                    SettingsRecoverySection(services: services, bridge: bridge)
                }
                .formStyle(.grouped)
                .frame(width: 600, height: 380)
            }
            Tab("Advanced", systemImage: "gearshape.2") {
                AdvancedSettingsScreen(services: services, bridge: bridge)
                    .formStyle(.grouped)
                    .frame(width: 600, height: 620)
            }
            Tab("Storage", systemImage: "internaldrive") {
                DeviceInfoScreen(services: services)
                    .formStyle(.grouped)
                    .frame(width: 600, height: 480)
            }
            if bridge.read({ $0.showLiveStats }) {
                Tab("Engine", systemImage: "slider.horizontal.3") {
                    EngineTweaksScreen(services: services, bridge: bridge)
                        .formStyle(.grouped)
                        .frame(width: 600, height: 620)
                }
            }
        }
        .onChange(of: bridge.version) {
            Task { await model.chat?.refreshSettings() }
        }
    }
}
#endif
