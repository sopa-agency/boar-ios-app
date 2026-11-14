import BoarAnswer
import SwiftUI

/// The home screen (android EmptyState): the mascot, name and tagline, then a few research ideas drawn for this chat
/// resting just above the question field. A tap asks one; a long press puts it in the field to edit first. The answer
/// style lives in the composer's style button.
struct ChatEmptyState: View {
    let noModel: Bool
    /// The question field has the keyboard: the ideas need the room, so the mascot steps aside (the header keeps one).
    let typing: Bool
    let chat: ChatController
    let onAsk: (String) -> Void
    let onFill: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        // Sits on the composer when it fits; scrolls when it doesn't (a notice on top, large text sizes).
        ScrollView {
            content
        }
        #if os(macOS)
        // A Mac window has room: the ideas sit in the middle.
        .defaultScrollAnchor(.center, for: .alignment)
        #else
        .defaultScrollAnchor(noModel ? .center : .bottom, for: .alignment)
        #endif
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { BuiltinLibraryRefresh.run(services: chat.services) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            LoadCrashNotice(chat: chat)
            if noModel {
                ContentUnavailableView {
                    Label("No Answer Model", icon: Symbols.model)
                } description: {
                    Text("Download an answer model to start asking questions.")
                } actions: {
                    Button("Open Models", action: openModels)
                        .buttonStyle(.boarProminent)
                }
            } else {
                #if os(iOS)
                if !typing { header.transition(.opacity) }
                #else
                header
                #endif
                ideas
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: typing)
    }

    /// BOAR's mascot, name and tagline over the ideas (android EmptyState).
    private var header: some View {
        VStack(spacing: 6) {
            Mascot(size: 96)
            Text(verbatim: "BOAR")
                .boarText("ui.headline")
                .foregroundStyle(.boar(.heading))
            Text("Answers from this \(Platform.deviceNoun), with sources")
                .boarText("ui.subtext")
                .fontWeight(.medium)
                .foregroundStyle(.boar(.success))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    /// The ideas drawn for this chat, each a topic over its question (android EmptyState's suggestions).
    @ViewBuilder private var ideas: some View {
        let shown = chat.suggestions.compactMap { key in PromptIdea.text(key).map { (key: key, idea: $0) } }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Research Topics")
                    .boarText("ui.caption")
                    .foregroundStyle(Color(palette.textSecondary))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(shown, id: \.key) { item in
                    ideaCard(topic: item.idea.topic, question: item.idea.question)
                }
            }
        }
    }

    private func ideaCard(topic: String, question: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic)
                .boarText("ui.caption")
                .fontWeight(.semibold)
                .foregroundStyle(Color(palette.textAccentEmerald))
            // Three lines at most: a whole idea, even in Portuguese at large text sizes.
            Text(question)
                .boarText("ui.body")
                .foregroundStyle(Color(palette.textPrimary))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(palette.bgCard), in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .onTapGesture { onAsk(question) }
        .onLongPressGesture { onFill(question) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Asks BOAR"))
        .accessibilityIdentifier("promptIdea")
        .accessibilityAction(named: Text("Edit Before Asking")) { onFill(question) }
    }

    private func openModels() {
        model.selection = .screen(.models)
    }
}
