import SwiftUI

/// One plugin's page (android `LabScaffold`): its picture, name and what it does with its own on/off switch, the review
/// note when it's under review, then the plugin's own content and, for a plugin with one, "About this plugin" folded.
///
/// The switch is on the page in every profile (adam, Nov 15): the chat's "X is off" line opens this page, so the user turns
/// it on where they land. Off, the page still shows everything (settings editable, saved for when it's on; editing never
/// turns it on, and an off plugin fills no slot). No "this plugin is off" banner (adam, Nov 13): the switch is in the list.
struct LabPage: View {
    let lab: any LabPlugin
    @State private var labs = Labs.shared
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if lab.fullPage {
                VStack(spacing: 0) {
                    if lab.status == .review, let review = lab.review { reviewNote(review) }
                    lab.content()
                }
                .toolbar { ToolbarItem(placement: .primaryAction) { PluginSwitch(lab: lab, fromPage: true) } }
            } else {
                BoarForm {
                    Section {
                        HStack(spacing: 12) {
                            PluginArt(lab: lab, side: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: lab.title)
                                    .font(.boar("ui.title"))
                                    .foregroundStyle(.boar(.heading))
                                    .lineLimit(1)
                                Text(verbatim: lab.body)
                                    .font(.boar("ui.caption"))
                                    .foregroundStyle(.boar(.muted))
                            }
                            Spacer(minLength: 0)
                            PluginSwitch(lab: lab, fromPage: true)
                        }
                    }
                    // UNDER REVIEW: the plugin works, but the user reads why before using it.
                    if lab.status == .review, let review = lab.review {
                        Section { reviewNote(review).listRowBackground(Color(palette.amberBgSubtle)) }
                    }
                    lab.content()
                    if let about = lab.about { AboutPluginFold(about: about) }
                }
            }
        }
        .background {
            if let presenter = lab.presenter() { presenter }
        }
        .navigationTitle(Text(verbatim: lab.title))
        .inlineNavigationTitle()
        // Opening the page counts as using the plugin: it moves up the header sheet's recent list.
        .task { labs.used(lab.id) }
    }

    private func reviewNote(_ review: String) -> some View {
        Label(review, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.boar(.warning))
    }
}
