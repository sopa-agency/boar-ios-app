import BoarAnswer
import BoarCore
import BoarModels
import SwiftUI

/// The chat (ChatScreen.tsx / ChatHeader.tsx): what BOAR is doing (or the model) under the title, the empty state with
/// suggestions, the streaming conversation, and the composer.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Bindable var chat: ChatController

    @State private var input = ""
    @State private var showingTones = false
    /// A lab's page opened from its toolbar badge.
    @State private var openLab: OpenLab?
    @State private var openSource: ChatSource?
    /// The header's mascot shown full screen.
    @State private var showingMascot = false
    #if os(macOS)
    /// The Mac shows sources in a trailing inspector beside the answer instead of a sheet.
    @State private var showingSources = false
    @State private var inspectedSource: ChatSource?
    #endif
    @State private var voice = VoiceInputController()
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette

    /// The mic shows when voice input is on in Settings and this iPhone has the on-device transcriber.
    private var voiceOn: Bool { chat.services.settings.voiceInputEnabled && VoiceInputController.supported }

    /// The model answering and where it runs (the steps card under the question shows what an answer is doing).
    private var subtitle: String {
        if chat.loadingModel { return String(localized: "Loading the model…") }
        guard let name = chat.modelName, !chat.noModel else { return String(localized: "No answer model") }
        return "\(name) · \(chat.modelPlace)"
    }

    /// The open chat's title; a new chat is just BOAR.
    private var title: String {
        guard !chat.messages.isEmpty, let id = chat.sessionId,
              let session = model.sessions.first(where: { $0.id == id }), !session.title.isEmpty else { return "BOAR" }
        return session.title
    }

    var body: some View {
        Group {
            if chat.messages.isEmpty {
                ChatEmptyState(noModel: chat.noModel, typing: composerFocused, chat: chat, onAsk: send)
            } else {
                ChatConversation(chat: chat, onReuse: reuse, onOpenSource: open)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Android's chat background (bgTerminal), under the bars too.
        .background(Color(palette.bgTerminal).ignoresSafeArea())
        .bottomBar {
            Composer(text: $input, focused: $composerFocused, toneSymbol: chat.currentTone.symbol, toneLabel: chat.currentTone.label,
                     deepResearch: chat.deepResearch, answering: chat.isAnswering, stopping: chat.stopping,
                     onSend: sendInput, onStop: chat.stop, onTones: showTones, voice: voiceOn ? voice : nil, chat: chat)
        }
        .navigationTitle(Text(verbatim: title))
        #if os(macOS)
        .navigationSubtitleIfAvailable(Text(subtitle))
        #endif
        .inlineNavigationTitle()
        .toolbar {
            // The switched-on labs' badges (android HeaderBadge): Boar Press's 📎 n opens its page over the chat.
            let badges = Labs.shared.active.compactMap { lab in lab.headerBadge(open: { openLab = OpenLab(id: lab.id) }).map { (lab.id, $0) } }
            if !badges.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 6) { ForEach(badges, id: \.0) { $0.1 } }
                }
            }
            #if os(macOS)
            // New Chat sits at the top of the sidebar (⌘N); the chat's own toolbar holds the sources inspector.
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showingSources) {
                    Label("Sources", systemImage: "sidebar.trailing")
                }
                .help(showingSources ? "Hide Sources" : "Show Sources")
            }
            #else
            // BOAR's mascot beside the title, as Android's header has it; a tap shows it big (ChatHeader).
            ToolbarItem(placement: .principal) {
                ChatTitle(title: title, subtitle: subtitle) { showingMascot = true }
            }
            ChatToolbar(chat: chat, onNewChat: model.newChat)
            #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingMascot) {
            MascotFullView { showingMascot = false }
        }
        #endif
        .sheet(isPresented: $showingTones) { ToneSheet(chat: chat) }
        .sheet(item: $openLab) { open in
            if let lab = Labs.shared.byId(open.id) {
                NavigationStack {
                    LabPage(lab: lab)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { openLab = nil } }
                        }
                }
            }
        }
        #if os(macOS)
        .inspector(isPresented: $showingSources) {
            SourceInspector(sources: inspectedSources, selected: $inspectedSource, technicalDetails: chat.technicalDetails)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 520)
        }
        .onChange(of: openSource) { _, source in
            guard let source else { return }
            inspectedSource = source
            showingSources = true
            openSource = nil
        }
        .onChange(of: chat.sessionId) { inspectedSource = nil }
        .onChange(of: model.citationRequest) { _, url in
            guard let url else { return }
            model.citationRequest = nil
            openCitation(url)
        }
        #else
        .sheet(item: $openSource) { source in
            SourceSheet(source: source, technicalDetails: chat.technicalDetails)
        }
        #endif
        .debugChatSheets(source: $openSource, tones: $showingTones, chat: chat)
        .overlay(alignment: .top) { ToastView(message: $chat.toast) }
        // Haptic feedback (Settings → Display): a tap on send, a success when the answer is done.
        .sensoryFeedback(.impact(weight: .light), trigger: chat.messages.count) { old, new in
            new > old && chat.services.settings.hapticsEnabled
        }
        .sensoryFeedback(.success, trigger: chat.isAnswering) { was, now in
            was && !now && chat.services.settings.hapticsEnabled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.cancel() }
        }
        .onAppear {
            // A new chat opens ready to type, as Messages and ChatGPT do.
            focusIfEmpty()
            // Boar Avatars: voice input used (android VoiceInput).
            let vault = chat.services.vault
            voice.onRecognized = { vault.record { $0.voice = true } }
        }
        .onChange(of: chat.messages.isEmpty) { _, empty in
            if empty { focusIfEmpty() }
        }
        // Setup's first question waits in the field; the user sends it.
        .onChange(of: chat.prefill, initial: true) { _, q in
            guard let q else { return }
            fill(q)
            chat.prefill = nil
        }
    }

    #if os(macOS)
    /// `boar-source://<n>/<answer id>`: source n of that answer (of the latest answer when the id is missing).
    private func openCitation(_ url: URL) {
        guard let n = Int(url.host() ?? ""), n >= 1 else { return }
        let id = url.path().split(separator: "/").first.map(String.init)?.removingPercentEncoding
        let answer = chat.messages.last { $0.id == id } ?? chat.messages.last { !$0.isUser && !$0.sources.isEmpty }
        guard let answer, n <= answer.sources.count else { return }
        open(answer.sources[n - 1])
    }

    /// The sources of the answer the inspected source belongs to; with none picked, the latest answer's sources.
    private var inspectedSources: [ChatSource] {
        if let picked = inspectedSource, let owner = chat.messages.last(where: { $0.sources.contains(picked) }) {
            return owner.sources
        }
        return chat.messages.last(where: { !$0.isUser && !$0.sources.isEmpty })?.sources ?? []
    }
    #endif

    private func focusIfEmpty() {
        guard chat.messages.isEmpty, !chat.noModel else { return }
        composerFocused = true
    }

    private func showTones() {
        showingTones = true
    }

    private func open(_ source: ChatSource) {
        openSource = source
    }

    private func fill(_ text: String) {
        input = text
        composerFocused = true
    }

    private func reuse(_ text: String) {
        fill(text)
        chat.toast = String(localized: "Question copied to the input")
    }

    private func sendInput() {
        send(input)
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !chat.isAnswering else { return }
        voice.cancel()
        chat.send(text)
        input = ""
        // The answer gets the whole screen: the keyboard closes on send.
        composerFocused = false
    }
}

/// A lab page shown over the chat, from its toolbar badge.
private struct OpenLab: Identifiable {
    let id: String
}
