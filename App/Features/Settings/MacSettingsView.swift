#if os(macOS)
import BoarCore
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
        let profile = bridge.read { $0.userProfile }
        TabView {
            Tab("General", systemImage: "gearshape") {
                BoarForm {
                    if SettingsPart.profile.shown(in: profile) {
                        Section {
                            MacProfileRow(bridge: bridge, profile: profile)
                        } header: {
                            BoarHeader { Text("Profile") }
                        }
                    }
                    if SettingsPart.tone.shown(in: profile) { SettingsToneSection(services: services, bridge: bridge) }
                    if SettingsPart.memory.shown(in: profile) { SettingsMemorySection(services: services, bridge: bridge) }
                    SettingsDisplaySection(bridge: bridge, profile: profile)
                    if SettingsPart.voice.shown(in: profile) { SettingsVoiceSection(bridge: bridge) }
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
            if LabsBuild.experimental && SettingsPart.experimentalShown(in: profile) {
                Tab("Experimental", systemImage: "flask") {
                    BoarForm {
                        SettingsExperimentalSection(services: services, bridge: bridge, profile: profile)
                    }
                    .formStyle(.grouped)
                    .frame(width: 600, height: 520)
                }
            }
            if SettingsPart.tweaks.shown(in: profile) {
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

/// The profile pills as a row of the General tab. A pick has no toast here: the line it would say sits under the pills.
private struct MacProfileRow: View {
    let bridge: SettingsBridge
    let profile: UserProfile

    var body: some View {
        HStack {
            ProfilePills(profile: profile) { p in
                bridge.settings.userProfile = p
                bridge.touch()
            }
            Spacer()
            Text(verbatim: ProfileCopy.gives(profile))
                .boarText("ui.subtext")
                .foregroundStyle(.boar(.muted))
        }
    }
}
#endif
