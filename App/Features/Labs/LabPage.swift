import SwiftUI

/// One experiment's page (android LabScaffold): its picture, name, status and what it does, the Enabled switch, the
/// review note when it's under review, then the lab's own content while it's on.
struct LabPage: View {
    let lab: any LabPlugin
    @State private var labs = Labs.shared
    @Environment(\.palette) private var palette

    var body: some View {
        BoarForm {
            Section {
                HStack(spacing: 12) {
                    if let art = lab.shownArt {
                        Image(art)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityHidden(true)
                    } else {
                        Text(verbatim: lab.emoji).font(.system(size: 36)).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(verbatim: lab.title)
                                .font(.boar("ui.title"))
                                .foregroundStyle(.boar(.heading))
                                .lineLimit(1)
                            LabStatusTag(status: lab.status)
                        }
                        Text(verbatim: lab.body)
                            .font(.boar("ui.caption"))
                            .foregroundStyle(.boar(.muted))
                    }
                }
                Toggle(isOn: Binding(get: { labs.enabled(lab.id) }, set: { labs.setEnabled(lab.id, $0) })) {
                    Text("Enabled")
                        .font(.boar("ui.titleSm"))
                        .foregroundStyle(.boar(.heading))
                    Text("Off: this lab disappears from the chat too.")
                        .font(.boar("mono.xs"))
                        .foregroundStyle(.boar(.dim))
                }
            }
            // UNDER REVIEW: the lab works, but the user reads why before using it.
            if lab.status == .review, let review = lab.review {
                // Android's amber note: the reason on the warning's wash.
                Section {
                    Label(review, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.boar(.warning))
                        .listRowBackground(Color(palette.amberBgSubtle))
                }
            }
            if labs.enabled(lab.id) {
                lab.content()
            } else {
                Section {
                    Text("This lab is off. Turn it on above.")
                        .font(.boar("ui.caption"))
                        .foregroundStyle(.boar(.muted))
                }
            }
        }
        .background {
            if let presenter = lab.presenter() { presenter }
        }
        .navigationTitle(Text(verbatim: lab.title))
        .inlineNavigationTitle()
    }
}
