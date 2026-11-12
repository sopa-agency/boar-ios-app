import SwiftUI

/// Settings → Boar Avatars while Boarverse is on (android `VaultEntry` in its own section, with the teaser): the way
/// into the grid. The count and the clues are inside.
struct SettingsAvatarsSection: View {
    let vault: TruffleVault
    #if os(macOS)
    /// The Settings window has no navigation stack: the grid opens as a sheet.
    @State private var showing = false
    #endif

    var body: some View {
        if vault.enabled {
            Section {
                #if os(macOS)
                Button {
                    showing = true
                } label: {
                    SettingsLabel("Open Boar Avatars", symbol: Symbols.avatars)
                }
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
                NavigationLink {
                    BoarAvatarsScreen(vault: vault)
                } label: {
                    SettingsLabel("Open Boar Avatars", symbol: Symbols.avatars)
                }
                .accessibilityIdentifier("settings.avatars")
                #endif
            } header: {
                BoarHeader {
                    Text("Boar Avatars")
                }
            } footer: {
                BoarFooter {
                    Text("Keep using BOAR and you’ll keep unlocking avatars: each one is a boar to wear, and some unlock new themes. Finding out what unlocks them is part of the fun.")
                }
            }
        }
    }
}
