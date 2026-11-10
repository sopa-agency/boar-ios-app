import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarModels
import SwiftUI

/// Settings (android SettingsScreen.kt, ModelSetupScreen.tsx's sections), shaped like an Apple app's Settings page: how
/// BOAR answers, what it answers with and searches (each opening its own screen), chats, appearance, privacy, voice,
/// then Advanced and the destructive actions last.
///
/// Not ported: Android's text size (Dynamic Type replaces it) and the language picker (iOS sets each app's language in
/// the system Settings app; the app follows it, English or Portuguese).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var bridge: SettingsBridge

    init(services: BoarServices) {
        self.services = services
        _bridge = State(initialValue: SettingsBridge(settings: services.settings))
    }

    var body: some View {
        BoarForm {
            SettingsToneSection(services: services, bridge: bridge)
            SettingsLibrarySection(services: services)
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
                    SettingsLabel("Advanced", symbol: Symbols.advanced)
                }
                NavigationLink {
                    AboutScreen()
                } label: {
                    SettingsLabel("About BOAR", symbol: "info")
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
