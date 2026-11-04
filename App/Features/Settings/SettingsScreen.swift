import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarModels
import SwiftUI

/// Settings (android SettingsScreen.kt, ModelSetupScreen.tsx's sections), shaped like an Apple app's Settings page: how
/// BOAR answers, chats, appearance, privacy, voice, then Advanced and the destructive actions last. Models and
/// Documents have their own screens in the sidebar.
///
/// Not ported: Android's text size (Dynamic Type replaces it) and the language picker (this build is English only).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var bridge: SettingsBridge

    init(services: BoarServices) {
        self.services = services
        _bridge = State(initialValue: SettingsBridge(settings: services.settings))
    }

    var body: some View {
        Form {
            SettingsToneSection(services: services, bridge: bridge)
            SettingsMemorySection(bridge: bridge)
            #if !os(macOS)
            SettingsFreeMemorySection(bridge: bridge)
            #endif
            SettingsDisplaySection(bridge: bridge)
            if let lock = model.lock { SettingsSecuritySection(lock: lock) }
            SettingsVoiceSection(bridge: bridge)
            Section {
                NavigationLink {
                    AdvancedSettingsScreen(services: services, bridge: bridge)
                } label: {
                    SettingsLabel("Advanced", symbol: "gearshape.2.fill", color: .gray)
                }
                NavigationLink {
                    AboutScreen()
                } label: {
                    SettingsLabel("About BOAR", symbol: "info", color: .gray)
                }
            }
            SettingsRecoverySection(services: services, bridge: bridge)
        }
        .navigationTitle(AppScreen.settings.title)
        .inlineNavigationTitle()
        .debugPush("settings-advanced") { AdvancedSettingsScreen(services: services, bridge: bridge) }
        .debugPush("settings-engine") { EngineTweaksScreen(services: services, bridge: bridge) }
        .debugPush("device-info") { DeviceInfoScreen(services: services) }
        .onDisappear {
            // The tone, Deep Research, technical details and model may have changed.
            Task { await model.chat?.refreshSettings() }
        }
    }
}
