import BoarCore
import SwiftUI

/// Settings → Boar Avatars (android `VaultScreen`): every avatar, unlocked in color with its name and date (or
/// Equipped), still locked as a dark square with "?" and its clue. A tap on an unlocked one equips it.
struct BoarAvatarsScreen: View {
    let vault: TruffleVault
    @Environment(\.palette) private var palette

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                Section {
                    ForEach(Vault.rules, id: \.id) { avatar in
                        cell(avatar.id, rule: avatar.rule)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(vault.state.unlocked.count) of \(Vault.rules.count) avatars unlocked")
                            .boarText("ui.titleLg")
                            .foregroundStyle(.boar(.heading))
                        Text("You unlock avatars by using BOAR. Everything is counted on this \(Platform.deviceNoun) and never leaves it.")
                            .boarText("ui.subtext")
                            .foregroundStyle(.boar(.muted))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .readableWidth()
        }
        .background(Color(palette.bgTerminal).ignoresSafeArea())
        .navigationTitle("Boar Avatars")
        .inlineNavigationTitle()
    }

    @ViewBuilder private func cell(_ id: String, rule: Vault.Rule) -> some View {
        if let at = vault.state.unlocked[id] {
            let equipped = vault.icon == id
            Button {
                vault.equip(id)
            } label: {
                card(equipped: equipped) {
                    picture(id)
                    Text(AvatarCopy.name(id))
                        .boarText("ui.body")
                        .fontWeight(.semibold)
                        .foregroundStyle(.boar(.heading))
                    Text(equipped ? String(localized: "Equipped") : String(localized: "Unlocked \(Self.date(at))"))
                        .boarText("ui.micro")
                        .foregroundStyle(.boar(equipped ? .success : .dim))
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(equipped ? .isSelected : [])
            .accessibilityIdentifier("vault.avatar.\(id)")
        } else {
            card(equipped: false) {
                ZStack {
                    // Android's SILHOUETTE matrix on opaque art: every pixel (18, 18, 24).
                    Color(red: 18 / 255, green: 18 / 255, blue: 24 / 255)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                    Text(verbatim: "?")
                        .boarText("ui.titleLg")
                        .foregroundStyle(.boar(.dim))
                }
                Text(AvatarCopy.clue(rule))
                    .boarText("ui.subtext")
                    .foregroundStyle(.boar(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Locked avatar. \(AvatarCopy.clue(rule))"))
            .accessibilityIdentifier("vault.avatar.\(id)")
        }
    }

    private func card(equipped: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4, content: content)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(palette.bgCard), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(equipped ? Color(palette.emerald500) : Color(palette.borderDefault), lineWidth: equipped ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
    }

    private func picture(_ id: String) -> some View {
        (TruffleArt.image(id) ?? Image(decorative: "Brand/mascot"))
            .resizable()
            .scaledToFit()
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    /// Android's `DateFormat.MEDIUM`: "Nov 12, 2026".
    private static func date(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .omitted)
    }
}
