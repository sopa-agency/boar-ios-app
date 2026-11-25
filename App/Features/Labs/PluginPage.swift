import SwiftUI

/// The plugin page template (android `PluginPage`, t9 and adam, Nov 12), in this order: one sentence of what it does, the
/// Try rows, and "How it works" folded with one real example (a before and after, or what you ask and what BOAR replies)
/// above the long note. A page with a live tool (Nomad, Lunar, Vitals) shows the tool first and this under it, with no
/// summary. Lives inside the page's Form, as its sections.
struct PluginPage: View {
    var summary: String?
    var before: String?
    var after: String?
    var tries: [String] = []
    var how: String?
    var beforeLabel: LocalizedStringResource = "BEFORE"
    var afterLabel: LocalizedStringResource = "AFTER"
    var exampleLabel: LocalizedStringResource?

    @Environment(\.palette) private var palette

    private var hasExample: Bool { before != nil || after != nil }

    var body: some View {
        if let summary {
            Section {
                Text(verbatim: summary)
                    .font(.boar("ui.bodyLg"))
                    .foregroundStyle(.boar(.primary))
            }
        }
        // The example sits inside "How it works", above its note (adam, Nov 13); a page with no such fold keeps it in a
        // card of its own.
        if hasExample && how == nil {
            Section { example }
        }
        if !tries.isEmpty {
            Section {
                ForEach(tries, id: \.self) { TryRow(question: $0) }
            } header: {
                Text("TRY IT")
            } footer: {
                BoarFooter { Text("Tap to ask it in a new chat. Hold to edit it first.") }
            }
        }
        if let how {
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        if hasExample { example }
                        Text(verbatim: how)
                            .font(.boar("ui.body"))
                            .foregroundStyle(.boar(.secondary))
                            .padding(.top, hasExample ? 6 : 0)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text("How it works")
                        .font(.boar("ui.body"))
                        .foregroundStyle(.boar(.heading))
                }
            }
        }
    }

    @ViewBuilder private var example: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let exampleLabel { label(exampleLabel) }
            // Labels only for a pair; a lone text is the example itself.
            let pair = before != nil && after != nil
            if let before {
                if pair { label(beforeLabel) }
                Text(verbatim: before)
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.secondary))
            }
            if let after {
                if pair { label(afterLabel) }
                Text(verbatim: after)
                    .font(.boar("ui.body").weight(pair ? .semibold : .regular))
                    .foregroundStyle(.boar(.primary))
            }
        }
    }

    private func label(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.boar("ui.caption").weight(.bold))
            .foregroundStyle(.boar(.muted))
    }
}

/// The template for a plugin that answers in the chat (android `AnswerPage`): its example is what you ask and what BOAR
/// replies.
struct AnswerPage: View {
    var summary: String?
    var question: String?
    var reply: String?
    var tries: [String] = []
    var how: String?

    var body: some View {
        PluginPage(summary: summary, before: question, after: reply, tries: tries, how: how,
                   beforeLabel: "You ask", afterLabel: "BOAR replies", exampleLabel: "EXAMPLE")
    }
}

/// A question to try (android's Try row, adam, Nov 12): a tap asks it in a new chat; a hold offers to put it in the box to
/// edit first (the iOS counterpart of Android's long press), or copy it.
struct TryRow: View {
    let question: String
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.askFromPlugin(question, send: true) } label: {
            Text(verbatim: "“\(question)”")
                .font(.boar("ui.subtext"))
                .foregroundStyle(.boar(.link))
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Ask it in a new chat", systemImage: "bubble.left") { model.askFromPlugin(question, send: true) }
            Button("Put it in the box to edit", systemImage: "pencil") { model.askFromPlugin(question, send: false) }
            Button("Copy the question", systemImage: "doc.on.doc") { Platform.copy(question) }
        }
        .accessibilityAddTraits(.isButton)
    }
}

/// "About this plugin", folded (android `AboutPluginFold`): the longer explanation the list's two-sentence line leaves out.
/// Shown only by a plugin with an `about` text.
struct AboutPluginFold: View {
    let about: String

    var body: some View {
        Section {
            DisclosureGroup {
                Text(verbatim: about)
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.secondary))
                    .padding(.vertical, 4)
            } label: {
                Text("About this plugin")
                    .font(.boar("ui.body"))
                    .foregroundStyle(.boar(.heading))
            }
        }
    }
}
