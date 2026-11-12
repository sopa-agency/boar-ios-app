import BoarCore
import SwiftUI

/// The theme (System, Campfire, Moonlight; Android's picker plus System), the avatar while Boarverse is on (android
/// `AvatarPicker`, under the theme), and haptics.
struct SettingsDisplaySection: View {
    @Environment(AppModel.self) private var model
    let bridge: SettingsBridge

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
            if let vault, vault.enabled {
                AvatarPicker(vault: vault)
            }
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
                Text("System follows your \(Platform.deviceNoun)'s appearance: Moonlight when dark, Paper when light.")
                // android ThemePicker: how many themes Boar Avatars still keeps closed.
                if let vault, vault.enabled {
                    let locked = ThemeTokens.all.count - ThemeTokens.available(boarverse: true, state: vault.state).count
                    if locked > 0 { Text("\(locked) more themes are unlocked by Labs and avatars.") }
                }
                #if !os(macOS)
                Text("Text size follows your \(Platform.deviceNoun)'s Dynamic Type setting.")
                #endif
            }
        }
    }
}

/// The equipped boar (android `AvatarPicker`): BOAR's own, then each unlocked avatar in the vault's order, in a row that
/// scrolls sideways.
private struct AvatarPicker: View {
    let vault: TruffleVault
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .body) private var side = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Boar")
                .boarText("ui.caption")
                .fontWeight(.semibold)
                .foregroundStyle(.boar(.secondary))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    avatar(nil)
                    ForEach(Vault.rules.map(\.id).filter(vault.unlocked), id: \.self) { avatar($0) }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
            // Android's own note; the iOS menu has no boar, so only the chat's changes.
            Text("Changes the boar in the chat.")
                .boarText("ui.subtext")
                .foregroundStyle(.boar(.muted))
        }
        .padding(.vertical, 4)
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
