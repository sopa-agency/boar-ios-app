import BoarCore
import SwiftUI

/// Experimental (android ExperimentalSection, shown from Explorer): adaptive routing first (Pro), the Boarverse switch
/// (Explorer), then the rows moved here in Pro (`SettingsMovedRows`), then the Boar Labs master switch (Pro). The switches
/// come together, the choices under them.
struct SettingsExperimentalSection: View {
    let services: BoarServices
    let bridge: SettingsBridge
    let profile: UserProfile
    @State private var labs = Labs.shared
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            if SettingsPart.adaptiveRouting.shown(in: profile) {
                Toggle(isOn: bridge.binding({ $0.adaptiveRoutingEnabled }, { $0.adaptiveRoutingEnabled = $1 })) {
                    SettingsLabel("Adaptive Routing", symbol: "arrow.triangle.branch")
                }
                .accessibilityIdentifier("settings.adaptiveRouting")
            }
            if SettingsPart.boarverseSwitch.shown(in: profile) {
                Toggle(isOn: Binding(get: { services.vault.enabled }, set: { services.vault.setEnabled($0) })) {
                    SettingsLabel("Boarverse", symbol: Symbols.avatars)
                }
                .accessibilityIdentifier("settings.boarverse")
            }
            if SettingsPart.tweaks.shown(in: profile) {
                SettingsMovedRows(bridge: bridge, profile: profile)
            }
            if SettingsPart.labsSettings.shown(in: profile) {
                Toggle(isOn: Binding(get: { labs.labsOn }, set: { labs.labsOn = $0 })) {
                    SettingsLabel("Plugins", symbol: Symbols.labs)
                }
                // android LabHooks.SettingsRow: the storage limit shows while Boar Labs is on.
                if labs.labsOn {
                    Picker(selection: Binding(get: { labs.storageLimit }, set: { labs.storageLimit = $0 })) {
                        ForEach(Labs.storageLimitChoices, id: \.self) { Self.storageLimitTitle($0).tag($0) }
                    } label: {
                        SettingsLabel("BOAR's Storage Limit", symbol: "internaldrive.fill")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings.storageLimit")
                }
            }
            // The list with a switch per plugin, in every profile (t9 1725).
            if labs.labsOn {
                Button { model.selection = .screen(.labs) } label: {
                    Text("Open Plugins").foregroundStyle(.boar(.link))
                }
                .accessibilityIdentifier("settings.openPlugins")
            }
        } header: {
            BoarHeader {
                Text("Experimental")
            }
        } footer: {
            BoarFooter {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile == .pro
                         ? "Extra tools in the menu and under answers. Each one can be switched on or off. Some start on; switch on the others you want in Plugins. If one misbehaves, switch it off and, if you can, open an issue on GitHub."
                         : "Extra tools in the menu and under answers. Each one can be switched on or off.")
                    if SettingsPart.adaptiveRouting.shown(in: profile) {
                        Text("Adaptive Routing picks the best installed model for each question.")
                    }
                    if SettingsPart.boarverseSwitch.shown(in: profile) {
                        Text("Unlock boar avatars as you use BOAR and wear them in the chat; some unlock new themes.")
                    }
                    if SettingsPart.tweaks.shown(in: profile) {
                        SettingsMovedNotes(bridge: bridge)
                    }
                    if SettingsPart.labsSettings.shown(in: profile) {
                        Text("Unfinished experiments in the menu and under answers. They may be slow, rough or change without notice.")
                        if labs.labsOn {
                            Text("How much space BOAR's models and packs may take. No Limit: only the \(Platform.deviceNoun)'s free space counts.")
                        }
                    }
                }
            }
        }
    }

    private static func storageLimitTitle(_ choice: String) -> Text {
        switch choice {
        case "auto": Text("Auto (50 GB)")
        case "none": Text("No Limit")
        default: Text(verbatim: "\(choice) GB")
        }
    }
}

/// Staged quotes, free memory (and after how long) and Show Technical Details: Pro's rows (android `MovedToExperimental`).
/// They sit in Experimental in a build with it, in Advanced otherwise. The switches first, the choice under them.
struct SettingsMovedRows: View {
    let bridge: SettingsBridge
    let profile: UserProfile

    var body: some View {
        if SettingsPart.stagedQuotes.shown(in: profile) {
            Toggle(isOn: bridge.binding({ $0.stagedQuotes }, { $0.stagedQuotes = $1 })) {
                SettingsLabel("Staged Quotes", symbol: "text.quote")
            }
            .accessibilityIdentifier("settings.stagedQuotes")
        }
        #if !os(macOS)
        Toggle(isOn: bridge.binding({ $0.freeMemoryInBackground }, { $0.freeMemoryInBackground = $1 })) {
            SettingsLabel("Free Memory When I Leave BOAR", symbol: Symbols.memory)
        }
        #endif
        if SettingsPart.technicalDetails.shown(in: profile) {
            Toggle(isOn: bridge.binding({ $0.showLiveStats }, { $0.showLiveStats = $1 })) {
                SettingsLabel("Show Technical Details", symbol: "chevron.left.forwardslash.chevron.right")
            }
        }
        #if !os(macOS)
        if bridge.read({ $0.freeMemoryInBackground }) {
            Picker(selection: bridge.binding({ $0.freeMemoryAfterMinutes }, { $0.freeMemoryAfterMinutes = $1 })) {
                Text("Auto").tag(Int?.none)
                Text("Immediately").tag(Int?.some(0))
                ForEach(FreeMemory.choicesMinutes, id: \.self) { m in
                    Text("\(m) min").tag(Int?.some(m))
                }
            } label: {
                SettingsLabel("Free Memory After", symbol: "timer")
            }
            .pickerStyle(.menu)
        }
        #endif
    }
}

/// What the moved rows say under them.
struct SettingsMovedNotes: View {
    let bridge: SettingsBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show the quotes from the sources before the answer. Turn it off if answers look wrong on your model.")
            #if !os(macOS)
            Text("Shortly after you leave, when nothing is being answered, BOAR unloads the model, so the phone doesn't close BOAR to get its memory back. The next answer takes a few seconds longer to start.")
            #endif
            Text("Shows timings under each answer, the live speed at the top of the chat, and the memory and storage bars in the menu.")
        }
    }
}
