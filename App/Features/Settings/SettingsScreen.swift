import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarModels
import SwiftUI

/// Settings (android SettingsScreen.kt, ModelSetupScreen.tsx's sections), shaped like an Apple app's Settings page. The
/// profile (Starter, Explorer, Pro: small pills in the header) decides what shows, by `SettingsPart`: how BOAR answers,
/// chats, Display & theme (with the Boar Avatar strip), voice, security, Advanced and Experimental (Pro and Explorer), then
/// Start Over, and About last. Models and Knowledge are in the menu, not here.
///
/// Not ported: Android's text size (Dynamic Type replaces it) and the language picker (iOS sets each app's language in
/// the system Settings app; the app follows it, English or Portuguese). A page this one opens (About, Advanced, Avatars)
/// returns to the same scroll: the navigation stack keeps it, and nothing here folds, so no open sections to remember
/// (android 7ab2fa6c).
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices
    @State private var bridge: SettingsBridge
    /// What a pick or an update says, for a few seconds (android Toasts).
    @State private var toast: String?
    @State private var toastSeconds = 1.8

    init(services: BoarServices) {
        self.services = services
        _bridge = State(initialValue: SettingsBridge(settings: services.settings))
    }

    var body: some View {
        let profile = bridge.read { $0.userProfile }
        BoarForm {
            if SettingsPart.tone.shown(in: profile) { SettingsToneSection(services: services, bridge: bridge) }
            if SettingsPart.memory.shown(in: profile) { SettingsMemorySection(services: services, bridge: bridge) }
            SettingsDisplaySection(bridge: bridge, profile: profile)
            if SettingsPart.voice.shown(in: profile) { SettingsVoiceSection(bridge: bridge) }
            if let lock = model.lock { SettingsSecuritySection(lock: lock) }
            if SettingsPart.tweaks.shown(in: profile) {
                Section {
                    NavigationLink {
                        AdvancedSettingsScreen(services: services, bridge: bridge)
                    } label: {
                        SettingsLabel("Advanced", symbol: Symbols.advanced)
                    }
                }
            }
            if LabsBuild.experimental && SettingsPart.experimentalShown(in: profile) {
                SettingsExperimentalSection(services: services, bridge: bridge, profile: profile)
            }
            SettingsRecoverySection(services: services, bridge: bridge)
            // Last, in every profile (android: the About row after Start over).
            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    SettingsLabel("About BOAR", symbol: "info")
                }
            }
        }
        .navigationTitle(AppScreen.settings.title)
        .inlineNavigationTitle()
        .toolbar {
            if SettingsPart.profile.shown(in: profile) {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) { pills(profile) }
                #else
                ToolbarItem(placement: .topBarTrailing) { pills(profile) }
                #endif
            }
        }
        .overlay(alignment: .top) { ToastView(message: $toast, seconds: toastSeconds) }
        .task { showUpdateNote(profile) }
        .debugPush("settings-advanced") { AdvancedSettingsScreen(services: services, bridge: bridge) }
        .debugPush("settings-engine") { EngineTweaksScreen(services: services, bridge: bridge) }
        .debugPush("device-info") { DeviceInfoScreen(services: services) }
        .debugPush("avatars") { BoarAvatarsScreen(vault: services.vault) }
        .onDisappear {
            // The tone, Deep Research, technical details and model may have changed.
            Task { await model.chat?.refreshSettings() }
        }
    }

    private func pills(_ profile: UserProfile) -> some View {
        ProfilePills(profile: profile) { p in
            let shown = ProfileCopy.pickToast(p, from: profile)
            bridge.settings.userProfile = p
            bridge.touch()
            withAnimation {
                toastSeconds = shown.seconds
                toast = shown.text
            }
        }
    }

    /// After an update that gave the install a profile, its note shows once on opening Settings, as a toast.
    private func showUpdateNote(_ profile: UserProfile) {
        guard bridge.settings.profileNotePending else { return }
        bridge.settings.profileNotePending = false
        withAnimation {
            toastSeconds = 7
            toast = ProfileCopy.updateToast(profile)
        }
    }
}
