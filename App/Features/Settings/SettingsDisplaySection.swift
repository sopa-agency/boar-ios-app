import BoarCore
import SwiftUI

/// Display & theme (android SettingsScreen): the theme (System plus Android's picker: Campfire, Moonlight, and Boar
/// Avatars' while Boarverse is on), the Boar Avatar strip while Boarverse is on (android `AvatarPicker`, under the
/// theme; no section of its own), speed while answering, and haptics from Explorer.
struct SettingsDisplaySection: View {
    @Environment(AppModel.self) private var model
    let bridge: SettingsBridge
    let profile: UserProfile

    var body: some View {
        let vault = model.services?.vault
        Section {
            Picker(selection: Binding(get: { model.theme }, set: { model.setTheme($0) })) {
                ForEach(model.themeChoices) { choice in
                    choice.title.tag(choice)
                }
            } label: {
                SettingsLabel("Theme", symbol: Symbols.theme)
            }
            .pickerStyle(.menu)
            if let vault, vault.enabled, SettingsPart.avatars.shown(in: profile) {
                AvatarPicker(vault: vault)
            }
            Toggle(isOn: bridge.binding({ $0.showLiveSpeed }, { $0.showLiveSpeed = $1 })) {
                SettingsLabel("Show speed while answering", symbol: "speedometer")
            }
            #if !os(macOS)
            if SettingsPart.haptics.shown(in: profile) {
                Toggle(isOn: bridge.binding({ $0.hapticsEnabled }, { $0.hapticsEnabled = $1 })) {
                    SettingsLabel("Haptics", symbol: "hand.tap.fill")
                }
            }
            #endif
        } header: {
            BoarHeader {
                Text("Display & Theme")
            }
        } footer: {
            BoarFooter {
                Text("System follows your \(Platform.deviceNoun)'s appearance: Moonlight when dark, Paper when light.")
                Text("Tokens per second, at the top of the chat while BOAR writes.")
                // android ThemePicker: how many themes Boar Avatars still keeps closed.
                if let vault, vault.enabled {
                    // The themes the menu lists (all but System), so a current one outside them (Paper from an older
                    // build) doesn't count as locked.
                    let locked = ThemeTokens.all.count - (model.themeChoices.count - 1)
                    if locked > 0 { Text("\(locked) more themes are unlocked by Labs and avatars.") }
                }
                #if !os(macOS)
                Text("Text size follows your \(Platform.deviceNoun)'s Dynamic Type setting.")
                #endif
            }
        }
    }
}

/// The Boar Avatar row (android `AvatarPicker`): BOAR's own, the one worn and the latest unlocked (`AvatarStrip`), and a
/// last box, "All ›", that opens the Boar Avatars page.
private struct AvatarPicker: View {
    let vault: TruffleVault
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .body) private var side = 52
    #if os(macOS)
    /// The Settings window has no navigation stack: the page opens as a sheet.
    @State private var showing = false
    #endif

    var body: some View {
        let strip = AvatarStrip.pick(unlocked: vault.state.unlocked, known: Vault.rules.map(\.id), equipped: vault.icon)
        VStack(alignment: .leading, spacing: 10) {
            Text("Boar Avatar")
                .boarText("ui.caption")
                .fontWeight(.semibold)
                .foregroundStyle(.boar(.secondary))
            HStack(spacing: 8) {
                ForEach(strip, id: \.self) { avatar($0) }
                all
            }
            .padding(.vertical, 3)
            // Android's notes; the iOS menu has no boar, and iOS changes the app icon at once (with its own alert).
            Text(TruffleVault.launcherIcons ? "Changes the boar in the chat and the app icon." : "Changes the boar in the chat.")
                .boarText("ui.subtext")
                .foregroundStyle(.boar(.muted))
        }
        .padding(.vertical, 4)
    }

    /// The last box: no count, the page has it.
    @ViewBuilder private var all: some View {
        #if os(macOS)
        Button { showing = true } label: { allBox }
            .buttonStyle(.plain)
            .sheet(isPresented: $showing) {
                NavigationStack {
                    BoarAvatarsScreen(vault: vault)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showing = false }
                            }
                        }
                }
                .macSheetSize(width: 560, height: 600)
            }
        #else
        NavigationLink { BoarAvatarsScreen(vault: vault) } label: { allBox }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.avatars")
        #endif
    }

    private var allBox: some View {
        Text("All ›")
            .boarText("ui.caption")
            .fontWeight(.semibold)
            .foregroundStyle(.boar(.link))
            .frame(width: side, height: side)
            .background(Color(palette.bgCard), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(palette.borderDefault), lineWidth: 1) }
            .contentShape(.rect)
    }

    private func avatar(_ id: String?) -> some View {
        let on = vault.icon == id
        return Button {
            vault.equip(id)
        } label: {
            TruffleArt.image(id, or: "Brand/boar")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(on ? Color(palette.emerald500) : Color(palette.borderDefault), lineWidth: on ? 3 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: AvatarCopy.name(id)))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("vault.pick.\(id ?? "boar")")
    }
}
