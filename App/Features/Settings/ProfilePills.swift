import BoarCore
import SwiftUI

/// The profile's names and the lines its pick says (android native.settings.profile.*).
enum ProfileCopy {
    static func name(_ p: UserProfile) -> LocalizedStringKey {
        switch p {
        case .simple: "Starter"
        case .explorer: "Explorer"
        case .pro: "Pro"
        }
    }

    static func nameText(_ p: UserProfile) -> String {
        switch p {
        case .simple: String(localized: "Starter")
        case .explorer: String(localized: "Explorer")
        case .pro: String(localized: "Pro")
        }
    }

    /// What a pick gives.
    static func gives(_ p: UserProfile) -> String {
        switch p {
        case .simple: String(localized: "Starter: set up the essentials.")
        case .explorer: String(localized: "Explorer: discover more features.")
        case .pro: String(localized: "Pro: advanced settings and tweaks.")
        }
    }

    /// What a pick shows, and for how long: going down adds what pauses.
    static func pickToast(_ p: UserProfile, from old: UserProfile) -> (text: String, seconds: Double) {
        let down = p.ordinal < old.ordinal
        return (gives(p) + (down ? " " + pauseNote : ""), down ? 4.5 : 2.8)
    }

    /// What a pick down adds.
    static var pauseNote: String {
        String(localized: "Advanced tweaks and plugin settings pause below Pro. Your settings are kept.")
    }

    /// The one-time note after an update gave the install a profile.
    static func updateToast(_ p: UserProfile) -> String {
        var text = String(localized: "New in this version: profiles. BOAR picked \(nameText(p)) from your settings. Change it any time.")
        if p != .pro {
            text += " " + String(localized: "Technical details (live speed at the top of the chat, the answer's performance details, the menu's memory and storage bars) are now in Pro.")
        }
        return text
    }
}

/// The profile as three small pills (android ProfilePills): the current one filled, one tap to switch. Each has a 44 pt
/// touch area and says whether it is selected.
struct ProfilePills: View {
    let profile: UserProfile
    let onPick: (UserProfile) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(UserProfile.allCases, id: \.self) { p in
                let on = p == profile
                Button {
                    if !on { onPick(p) }
                } label: {
                    Text(ProfileCopy.name(p))
                        .boarText("ui.caption")
                        .fontWeight(on ? .bold : .regular)
                        .lineLimit(1)
                        .foregroundStyle(on ? Color(palette.textInverse) : Color(palette.textPrimary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(on ? Color(palette.emerald600) : Color(palette.bgCard), in: .capsule)
                        .overlay { Capsule().strokeBorder(on ? Color(palette.emerald600) : Color(palette.borderDefault), lineWidth: 1) }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ProfileCopy.name(p))
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("settings.profile.\(p.key)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
