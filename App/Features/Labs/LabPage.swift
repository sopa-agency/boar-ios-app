import SwiftUI

/// One experiment's page (android LabScaffold): its picture, name, status and what it does, the Enabled switch, the
/// review note when it's under review, then the lab's own content while it's on.
struct LabPage: View {
    let lab: any LabPlugin
    @State private var labs = Labs.shared

    var body: some View {
        Form {
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
                                .font(.headline)
                                .lineLimit(1)
                            LabStatusTag(status: lab.status)
                        }
                        Text(verbatim: lab.body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(get: { labs.enabled(lab.id) }, set: { labs.setEnabled(lab.id, $0) })) {
                    Text("Enabled")
                    Text("Off: this lab disappears from the chat too.")
                }
            }
            // UNDER REVIEW: the lab works, but the user reads why before using it.
            if lab.status == .review, let review = lab.review {
                Section {
                    Label(review, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if labs.enabled(lab.id) {
                lab.content()
            } else {
                Section {
                    Text("This lab is off. Turn it on above.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: lab.title))
        .inlineNavigationTitle()
    }
}
