import BoarCore
import SwiftUI

/// What hides the plugins that aren't out yet and the status tags (android `PluginsUi`, adam, Nov 12): kept so they can come
/// back to promote what's next. The tile view of Plugins is gone on iOS; the list is the only view, as on Android.
enum PluginsUi {
    /// Plugins in testing with no release date (the classified teasers).
    static let showUpcoming = false
    /// The ALPHA/BETA/LIVE tags: dropped from what users see; the status stays an internal gate.
    static let showStatus = false
}

/// Plugins (android `LabsList`, v2.0.0): one row per plugin with its picture, name, a line of what it does and an on/off
/// switch, so nothing needs a page just to switch on. A tap on the row opens the plugin's page. In every profile.
struct LabsScreen: View {
    @State private var labs = Labs.shared
    @Environment(\.palette) private var palette
    @State private var query = ""

    var body: some View {
        let open = labs.visible.filter { labs.opened($0) != nil }
        let shown = open.filter { RecentPlugins.matches(query, $0.title, $0.body) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Subtitles only where a first-timer needs one (adam, Nov 12).
                Text("Switch them on or off, tap to open.")
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.muted))
                ForEach(shown, id: \.id) { lab in PluginRow(lab: lab) }
                if shown.isEmpty {
                    Text("No plugin matches.")
                        .font(.boar("ui.caption"))
                        .foregroundStyle(.boar(.muted))
                }
            }
            .padding()
            .readableWidth()
        }
        .background(Color(palette.bgSurface).ignoresSafeArea())
        .searchable(text: $query, prompt: Text("Search plugins"))
        .navigationTitle("Plugins")
        .inlineNavigationTitle()
        .navigationDestination(for: LabRoute.self) { route in
            if let lab = labs.byId(route.id) { LabPage(lab: lab) }
        }
        .debugPush("lab-\(DebugLaunch.labId ?? "")") {
            if let lab = DebugLaunch.labId.flatMap(labs.byId) { LabPage(lab: lab) }
        }
    }
}

/// A plugin's page in the Plugins stack.
struct LabRoute: Hashable {
    let id: String
}

/// One plugin in the list: tap the row for its page, flip the switch to turn it on or off right here. One look, on or off:
/// the switch says which (adam, 23 Nov).
private struct PluginRow: View {
    let lab: any LabPlugin
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: LabRoute(id: lab.id)) {
                HStack(spacing: 10) {
                    PluginArt(lab: lab, side: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: lab.title)
                            .font(.boar("ui.body").weight(.semibold))
                            .foregroundStyle(.boar(.heading))
                            .lineLimit(1)
                        Text(verbatim: lab.body)
                            .font(.boar("ui.caption"))
                            .foregroundStyle(.boar(.muted))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            PluginSwitch(lab: lab, fromPage: false)
        }
        .padding(10)
        .background(Color(palette.bgCard), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(palette.borderSubtle)))
    }
}

/// A plugin's picture at list size, or its emoji until it has one.
struct PluginArt: View {
    let lab: any LabPlugin
    var side: CGFloat = 44
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Color(palette.bgCardElevated)
            if let art = lab.shownArt {
                Image(art).resizable().scaledToFill()
            } else {
                Text(verbatim: lab.emoji).font(.system(size: side * 0.55))
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side > 40 ? 8 : 6))
        .accessibilityHidden(true)
    }
}

/// A plugin's on/off switch (android `PluginPageSwitch`, and the list's own): turning the safety plugin off asks first, in
/// every profile (`PluginReach`), and `Labs.setEnabled` refuses it unasked. `fromPage`: the switch on the plugin's own
/// page, where an off plugin stays listed in the header sheet.
struct PluginSwitch: View {
    let lab: any LabPlugin
    let fromPage: Bool
    @State private var labs = Labs.shared
    @State private var asking = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { labs.enabled(lab.id) },
            set: { on in
                if PluginReach.asksBeforeOff(lab.id, turningOn: on) { asking = true } else { labs.setEnabled(lab.id, on, fromPage: fromPage) }
            }
        )) {
            Text("\(lab.title) on or off")
        }
        .labelsHidden()
        .safetyOffAlert(isPresented: $asking) { labs.setEnabled(lab.id, false, fromPage: fromPage, confirmed: true) }
    }
}

extension View {
    /// The question before a safety plugin goes off: "Turn off the carbon monoxide safety card?". `off` runs only on
    /// "Turn off"; Cancel changes nothing.
    func safetyOffAlert(isPresented: Binding<Bool>, off: @escaping () -> Void) -> some View {
        alert("Turn off the carbon monoxide safety card?", isPresented: isPresented) {
            Button("Turn off", role: .destructive, action: off)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BOAR will no longer show the carbon monoxide warning first when a question sounds like poisoning. You can turn it back on from its page.")
        }
    }
}
