import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarModels
import Foundation
import Observation

/// The screens reachable from the sidebar besides the chat (`DestinationScreen`).
enum AppScreen: String, Hashable, CaseIterable, Identifiable {
    case documents, models, settings, evaluation, about
    var id: String { rawValue }

    /// The sidebar's Library rows. Settings is the sidebar's top-left button; About is inside Settings and the
    /// benchmark in Settings → Advanced.
    static let sidebarCases: [AppScreen] = [.documents, .models]

    var title: String {
        switch self {
        case .documents: String(localized: "Knowledge")
        case .models: String(localized: "Models")
        case .settings: String(localized: "Settings")
        case .evaluation: String(localized: "Evaluation")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .documents: Symbols.library
        case .models: Symbols.model
        case .settings: "gearshape"
        case .evaluation: Symbols.benchmark
        case .about: "info.circle"
        }
    }
}

/// What the split view's sidebar has selected: the open chat (a saved session or a new one) or another screen.
enum SidebarItem: Hashable {
    case newChat
    case session(String)
    case screen(AppScreen)
}

/// A menu command (Mac) that the sidebar carries out: focus its search, or ask to rename or delete a chat.
enum SidebarRequest: Equatable {
    case find
    case rename(String)
    case delete(String)
}

/// The app's root state (iOS counterpart of android `BoarServices` + MainActivity's screen switch): opens the engine
/// services off the main actor, decides between setup and the chat, and owns the controllers the screens observe.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching
        case setup
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .launching
    private(set) var services: BoarServices?
    private(set) var chat: ChatController?
    private(set) var setup: SetupFlow?
    private(set) var sessions: [ChatSession] = []
    /// The catalog (downloads keep going on other screens), documents, evaluation and the app lock.
    private(set) var models: ModelsController?
    private(set) var documents: DocumentsController?
    private(set) var evaluation: EvaluationController?
    private(set) var lock: AppLock?
    @ObservationIgnored private let spotlight = SpotlightDonor()
    var selection: SidebarItem? = .newChat
    /// System / Light / Dark (Settings → Display); persisted on every change.
    var appearance: AppAppearance = .system {
        didSet { services?.settings.themeId = appearance.rawValue }
    }
    let connectivity = Connectivity()
    /// Set by a menu command, cleared by the sidebar once it acts on it.
    var sidebarRequest: SidebarRequest?
    /// A citation link the system handed back (Mac): `boar-source://<n>/<answer id>`; the chat opens that source.
    var citationRequest: URL?
    /// File → Import Documents… (Mac): the Documents screen opens its file picker.
    var importRequest = false
    /// Setup was opened from the app (Settings → Recovery): it offers the way back.
    private(set) var setupFromApp = false

    /// Opens the engine (SQLite, catalog, packs registry) on a background task, then shows setup or the chat.
    func start() async {
        guard services == nil else { return }
        BackgroundDownloads.shared.activate()
        PerfMonitor.start()
        #if DEBUG
        DemoFiles.reset()
        #if os(macOS)
        DebugSnapshot.scheduleIfRequested()
        #endif
        #endif
        do {
            let open = BoarPerf.begin("services.open")
            let services = try await Task.detached(priority: .userInitiated) { try BoarServices() }.value
            open.end()
            self.services = services
            Self.migrateTechnicalDetails(services)
            #if DEBUG
            await DemoSeed.run(services: services)
            if let remote = DebugLaunch.remote {
                services.backend = .remote
                RemoteConfig.setAddress(remote, services.settings)
            }
            #endif
            appearance = AppAppearance(storedId: services.settings.themeId)
            let chat = ChatController(services: services)
            chat.onSessionsChanged = { [weak self] in self?.reloadSessions() }
            self.chat = chat
            wireFeatures(services, chat: chat)
            // Setup is complete when everything required and an answer model are on disk (file checks, off the main actor).
            let complete = (try? await services.background { $0.assets.requiredPresent() }) ?? false
            let setup = SetupFlow(services: services)
            if complete && !setup.unfinished {
                phase = .ready
                // The demo's "installed" models are empty files: nothing may try to load them. The load starts 600 ms
                // after the chat appears, past its first render: on the iPhone 13 (2 performance cores) loading
                // alongside that render made a ~0.3 s launch microhang.
                if !DebugLaunch.demo || services.backend == .remote {
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        chat.preload()
                    }
                }
                reloadSessions()
                drainInbox()
            } else {
                self.setup = setup
                phase = .setup
            }
            #if DEBUG
            Task { await DebugRouter.apply(self) }
            #endif
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// This build starts with technical details hidden (speeds, token counts, match scores), once: a lay user sees plain
    /// answers; Settings → Advanced → Show Technical Details turns them back on. The engine's default is untouched.
    private static func migrateTechnicalDetails(_ services: BoarServices) {
        let key = "ui.techDetailsOff.v1"
        let defaults = AppPaths.defaults
        guard !defaults.bool(forKey: key) else { return }
        services.settings.showLiveStats = false
        defaults.set(true, forKey: key)
    }

    /// The feature controllers and how they talk to the chat.
    private func wireFeatures(_ services: BoarServices, chat: ChatController) {
        let models = ModelsController(services: services)
        let evaluation = EvaluationController(services: services)
        models.onModelChanged = { [weak chat, weak evaluation] in
            chat?.refreshModel()
            evaluation?.reloadConfigs()
        }
        evaluation.chatBusy = { [weak chat] in chat?.isAnswering ?? false }
        let lock = AppLock(services: services)
        lock.onUnlocked = { [weak self] in
            guard let self else { return }
            self.reloadSessions()
            self.drainInbox()
        }
        self.models = models
        self.evaluation = evaluation
        self.documents = DocumentsController(services: services)
        self.lock = lock
        #if DEBUG
        // The bench harness drops device requests in Documents/eval/requests (debug builds, as on Android).
        evaluation.startPolling()
        #endif
    }

    // MARK: Siri, Shortcuts and Spotlight

    /// Runs what Siri or Spotlight asked for once BOAR is ready and unlocked: a question on a new chat, or a saved chat.
    func drainInbox() {
        guard case .ready = phase, let chat, lock?.locked != true else { return }
        let inbox = IntentInbox.shared
        if let id = inbox.sessionId, !chat.isAnswering {
            inbox.sessionId = nil
            selection = .session(id)
        }
        if let q = inbox.question, !chat.isAnswering {
            inbox.question = nil
            newChat()
            chat.send(q)
        }
    }

    // MARK: setup

    /// Setup ended ("Open BOAR"): the chat, with the model it installed.
    func finishSetup() {
        setup?.forget()
        setup = nil
        setupFromApp = false
        phase = .ready
        guard let chat else { return }
        Task {
            await chat.refreshSettings()
            chat.preload()
        }
        reloadSessions()
        drainInbox()
    }

    /// Settings → Recovery: the wizard again; the chat stays one tap away.
    func reopenSetup() {
        guard let services else { return }
        let flow = setup ?? SetupFlow(services: services)
        flow.restart()
        setup = flow
        setupFromApp = true
        phase = .setup
    }

    // MARK: sessions sidebar

    func reloadSessions() {
        guard let services else { return }
        Task {
            let list = (try? await services.background { try $0.chats.listSessions() }) ?? []
            self.sessions = list
            // Spotlight gets the titles while the lock is off (sealed titles never reach the system index).
            let locked = self.lock?.enabled ?? false
            let spotlight = self.spotlight
            Task.detached(priority: .utility) { await spotlight.sync(list, locked: locked) }
            // A new chat got its session: highlight it without reopening it.
            if let open = self.chat?.sessionId, self.selection == .newChat { self.selection = .session(open) }
        }
    }

    /// The sidebar's selection changed: open that chat, or start a new one.
    func select(_ item: SidebarItem?) {
        guard let chat else { return }
        switch item {
        case .newChat: if chat.sessionId != nil { chat.newChat() }
        case .session(let id): chat.openSession(id)
        case .screen, .none: break
        }
    }

    func newChat() {
        chat?.newChat()
        selection = .newChat
    }

    /// After an import, "Ask about them": a new chat in the Personal Files style, which answers only from the files.
    func askAboutFiles() {
        documents?.imported = nil
        chat?.setTone("personal")
        newChat()
    }

    func deleteSession(_ id: String) async {
        await chat?.deleteSession(id)
        if selection == .session(id) { selection = .newChat }
        reloadSessions()
    }

    func renameSession(_ id: String, to title: String) async {
        await chat?.renameSession(id, to: title)
    }

    // MARK: model seam choice

    /// Apple's on-device model can answer on this phone (Apple Intelligence on, model ready).
    var appleModelAvailability: AppleModelAvailability { AppleModelAvailability.current }

    var backend: ModelBackend { services?.backend ?? .llama }

    /// The Settings picker: a new choice switches the backend.
    var backendChoice: ModelBackend {
        get { backend }
        set { Task { await setBackend(newValue) } }
    }

    /// Switches between llama.cpp (a downloaded GGUF) and Apple's on-device model; the next answer loads it.
    func setBackend(_ backend: ModelBackend) async {
        guard let services, services.backend != backend else { return }
        services.backend = backend
        await services.host.unload()
        chat?.refreshModel()
        chat?.preload()
    }

    // MARK: lifecycle

    /// The open chat's id, when a saved chat is selected.
    var selectedSessionId: String? {
        if case .session(let id) = selection { id } else { nil }
    }

    /// The app went to the background: Metal work is not allowed there on iPhone, so a running answer stops (its text is
    /// kept). A Mac keeps answering behind other windows and while minimized.
    func didEnterBackground() {
        #if !os(macOS)
        chat?.stop()
        #endif
        lock?.lockOnBackground()
    }

    func didBecomeActive() {
        setup?.onForeground()
        drainInbox()
    }
}
