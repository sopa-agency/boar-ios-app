import BoarAnswer
import SwiftUI

/// The home screen: a few topic rows resting just above the question field (the keyboard opens with it). A tap on a topic
/// shows its questions in their place, each answered by the built-in library. The answer style lives in the composer's
/// style button.
struct ChatEmptyState: View {
    let noModel: Bool
    /// The question field has the keyboard: the topics need the room, so the mascot steps aside (the header keeps one).
    let typing: Bool
    let chat: ChatController
    let onAsk: (String) -> Void
    @Environment(AppModel.self) private var model
    /// The topic whose questions are showing; nil shows the topics.
    @State private var openTopic: String?

    var body: some View {
        // Sits on the composer when it fits; scrolls when it doesn't (a notice on top, large text sizes).
        ScrollView {
            content
        }
        #if os(macOS)
        // A Mac window has room: the topics sit in the middle as a grid, under a heading.
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
                let topics = HomeTopic.all
                if let topic = topics.first(where: { $0.id == openTopic }) {
                    TopicQuestions(topic: topic, onAsk: onAsk, onBack: { show(nil) })
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    #if os(macOS)
                    topicGrid(topics)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    #else
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(topics) { topic in
                            TopicRow(topic: topic, onOpen: { show(topic.id) })
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    #endif
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: typing)
    }

    /// BOAR's mascot, name and tagline over the topics (android EmptyState).
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

    #if os(macOS)
    private func topicGrid(_ topics: [HomeTopic]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What do you want to know?")
                    .font(.largeTitle.bold())
                Text("Pick a topic for ideas, or type your own question below.")
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(topics) { topic in
                    Button {
                        show(topic.id)
                    } label: {
                        Label {
                            Text(topic.name)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: topic.symbol)
                                .foregroundStyle(topic.color)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint(Text("Shows questions to ask"))
                }
            }
        }
    }
    #endif

    private func show(_ topic: String?) {
        withAnimation(.snappy) { openTopic = topic }
    }

    private func openModels() {
        model.selection = .screen(.models)
    }
}
