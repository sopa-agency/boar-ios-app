import SwiftUI

/// The chat header icon's sheet (android `LabHooks.HeaderBadges`): the last three plugins used among those on, newest
/// first, each opening its page; the plugins switched off from their pages (and an off safety plugin) under OFF, one tap
/// from their switch; and Manage plugins, the list with every switch. The rest of the plugins are one tap away there.
///
/// A plugin's page opens inside the sheet (a push, Back returns to the list) rather than on top of it, which is how an
/// iPhone sheet takes a second level; Android navigates to the page and closes the sheet.
struct PluginsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var labs = Labs.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(labs.recentShown, id: \.id) { lab in
                        NavigationLink(value: LabRoute(id: lab.id)) {
                            SheetRow(lab: lab, trailing: count(lab))
                        }
                    }
                } header: {
                    Text("RECENT PLUGINS")
                }
                let off = labs.offListed
                if !off.isEmpty {
                    Section {
                        ForEach(off, id: \.id) { lab in
                            NavigationLink(value: LabRoute(id: lab.id)) {
                                SheetRow(lab: lab, trailing: String(localized: "Off"), off: true)
                            }
                        }
                    } header: {
                        Text("OFF")
                    }
                }
                // The list with every switch, in every profile (t9 1725).
                Section {
                    Button {
                        dismiss()
                        model.selection = .screen(.labs)
                    } label: {
                        Text("Manage plugins ›")
                            .font(.boar("ui.body").weight(.bold))
                            .foregroundStyle(.boar(.success))
                    }
                }
            }
            .navigationTitle("Plugins")
            .inlineNavigationTitle()
            .navigationDestination(for: LabRoute.self) { route in
                if let lab = labs.byId(route.id) { LabPage(lab: lab) }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }

    /// The plugin's own count beside it (Press's basket), when it has one.
    private func count(_ lab: any LabPlugin) -> String? {
        let n = lab.headerCount()
        return n > 0 ? lab.headerCountLabel(n) : nil
    }
}

/// One row of a plugins sheet: a 32 pt picture, the name, a line under it, and what's on the right.
private struct SheetRow: View {
    let lab: any LabPlugin
    let trailing: String?
    var off = false

    var body: some View {
        HStack(spacing: 12) {
            PluginArt(lab: lab, side: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: lab.title)
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.primary))
                    .lineLimit(1)
                Text(verbatim: lab.body)
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(verbatim: trailing)
                    .font(.boar("mono.xs").weight(.bold))
                    .foregroundStyle(.boar(off ? .muted : .success))
            }
        }
    }
}
