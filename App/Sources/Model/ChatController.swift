import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarModels
import BoarRAG
import BoarRouting
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Synchronization

/// The chat (port of android `ChatViewModel`, itself ChatScreen.tsx's send flow): Deep Research when it's on, adaptive
/// routing when that's on, the default answer path otherwise. The answer streams into its message; both turns are saved
/// with the answer's sources and receipt. Stop cancels the generation in flight and the stages after it.
@MainActor
@Observable
final class ChatController {
    /// Messages sent verbatim as history (ChatScreen.tsx VERBATIM_MESSAGE_COUNT).
    static let verbatimMessageCount = 6

    private(set) var sessionId: String?
    private(set) var messages: [ChatItem] = []
    private(set) var answeringId: String?
    private(set) var activity: ChatActivity?
    private(set) var liveTokPerSec: Double?
    /// While adaptive routing has another model write the answer: that model's name (android `answeringModel`; the header
    /// says "→ name"). Nil otherwise.
    private(set) var answeringModel: String?
    /// The answering model's catalog label (the receipt keeps it).
    private(set) var modelLabel: String?
    /// The answering model's plain name ("Fast", "Accurate"), for the chat's subtitle.
    private(set) var modelName: String?
    /// Where it runs: "on this \(Platform.deviceNoun)", "on this Mac", "on mac-mini.local:8080".
    private(set) var modelPlace = String(localized: "on this \(Platform.deviceNoun)")
    private(set) var noModel = false
    private(set) var technicalDetails = false
    /// The live tok/s pill at the top of the chat (android showLiveSpeed); its own switch, off by default.
    private(set) var liveSpeed = false
    private(set) var loadingModel = false
    private(set) var personalityId: String
    private(set) var stopping = false
    /// The prompt ideas of the empty chat, as keys of `PromptIdea`.
    private(set) var suggestions: [String] = []
    /// Every idea this model and language can show; `suggestions` is a few of them.
    private var ideaPool: [String] = []
    private(set) var deepResearch = false
    /// A failure before the answer row exists (the chat couldn't be created).
    var error: String?
    /// CR-2, shown once: the model that closed the app and the one answering instead. Also the note for a model that
    /// closed the app and that no other model can stand in for (StartLoad.noFallback), shown at each start.
    var loadCrash: LoadGuard.Crash?
    /// The answer model may not fit this device's memory (StartLoad.askRisky): it isn't loaded until the user chooses.
    var riskyLoad: RiskyLoad?
    /// A question asked while the memory note's model wasn't loaded: sent once the user loads it.
    @ObservationIgnored private var heldQuestion: String?
    /// A new chat under a limit the user set: asked before it deletes the oldest (PruneNote); the first question waits.
    var pruneNote: PruneNote?
    @ObservationIgnored private var prunedQuestion: PrunedQuestion?
    @ObservationIgnored private var pruneAccepted = false
    /// A short message over the chat (Toast.tsx): the new tone, a reused question.
    var toast: String?
    /// Setup's first question (android ChatViewModel prefill): the chat puts it in the field, unsent, and clears this.
    var prefill: String?
    /// Questions sent while BOAR answers, waiting their turn (PromptQueue), first to run first.
    private(set) var queued: [QueuedPrompt] = []

    @ObservationIgnored let services: BoarServices
    /// Called after a session is created, renamed by the model, or pruned (the sidebar reloads).
    @ObservationIgnored var onSessionsChanged: (@MainActor () -> Void)?
    @ObservationIgnored private var job: Task<Void, Never>?
    /// A chat title or summary still being written; a new question stops it (one model, one generation).
    @ObservationIgnored private var background: Task<Void, Never>?
    @ObservationIgnored private let stopFlag = StopFlag()
    /// A tap on an instant answer being typed shows all of it (android skipTyping).
    @ObservationIgnored private var skipTyping = false
    /// The queue and what it decides (PromptQueueFlow); in memory, its size kept so a closed app can say what it dropped.
    @ObservationIgnored private let flow = PromptQueueFlow(store: .defaults(AppPaths.defaults, key: "boar.chat.queueWaiting"))

    init(services: BoarServices) {
        self.services = services
        personalityId = services.settings.personalityId ?? services.personalities.defaultId
        deepResearch = services.settings.deepResearchMode
        technicalDetails = services.settings.showLiveStats
        liveSpeed = services.settings.showLiveSpeed
        refreshModel()
        flow.onChange = { [weak self] in
            guard let self else { return }
            queued = flow.waiting.map { QueuedPrompt(id: $0.id, text: $0.text) }
        }
        // Questions that were waiting when the app was closed are gone: say so, once.
        if let n = flow.droppedAtStart() { toast = String(localized: "BOAR was closed: \(n) waiting questions were dropped.") }
    }

    var isAnswering: Bool { answeringId != nil }

    // MARK: settings the chat shows

    /// The styles the tone sheet offers: "custom" only when a custom prompt is written.
    var tones: [Personality] {
        let custom = !(services.settings.customSystemPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return services.personalities.personalities.filter { $0.id != "custom" || custom }
    }

    var currentTone: Personality { services.personalities.get(personalityId) }

    func setTone(_ id: String) {
        services.settings.personalityId = id
        personalityId = id
        toast = String(localized: "Answers will be \(services.personalities.get(id).displayLabel)")
    }

    /// Deep Research as a bindable value (the answer-style sheet's toggle); writes go through `setDeepResearch`.
    var deepResearchEnabled: Bool {
        get { deepResearch }
        set { setDeepResearch(newValue) }
    }

    func setDeepResearch(_ on: Bool) {
        services.settings.deepResearchMode = on
        deepResearch = on
    }

    /// Back from settings: the tone, Deep Research and model may have changed.
    func refreshSettings() async {
        personalityId = services.settings.personalityId ?? services.personalities.defaultId
        deepResearch = services.settings.deepResearchMode
        technicalDetails = services.settings.showLiveStats
        liveSpeed = services.settings.showLiveSpeed
        refreshModel()
        takeFirstQuestion()
        // The open chat was erased (Clear all chat history, a forgotten PIN): start a new one.
        if let open = sessionId {
            let exists = (try? await services.background { try $0.chats.listSessions().contains { $0.id == open } }) ?? true
            if !exists {
                flow.clear()
                newChat()
            }
        }
    }

    /// The question picked in setup's guide, once: read and cleared, so it doesn't come back on the next launch.
    private func takeFirstQuestion() {
        guard let q = services.settings.pendingFirstQuestion else { return }
        services.settings.pendingFirstQuestion = nil
        prefill = q
    }

    /// After setup or a model change: the answering model's name, or that there's none.
    func refreshModel() {
        let m = services.answerModel()
        if services.backend == .apple && AppleModelAvailability.current.isAvailable {
            modelLabel = String(localized: "Apple on-device model")
            modelName = modelLabel
            modelPlace = String(localized: "on this \(Platform.deviceNoun)")
            noModel = false
        } else if services.backend == .remote, let server = RemoteConfig.server(services.settings) {
            modelLabel = services.host.current.map { $0.info.name } ?? server.displayName
            // "Qwen2.5-1.5B-Instruct-Q4_K_M" → "Qwen2.5-1.5B-Instruct": the quantization says nothing to a reader.
            modelName = services.host.current.map { shortModelLabel($0.info.name).replacing(/[-_.](I?Q\d\w*|BF16|F16|F32)$/, with: "") }
                ?? String(localized: "Network model")
            modelPlace = String(localized: "on \(server.displayName)")
            noModel = false
        } else {
            modelPlace = String(localized: "on this \(Platform.deviceNoun)")
            modelLabel = m.map { shortModelLabel($0.label) }
            modelName = m?.friendlyName
            noModel = m == nil
        }
        let installed = services.catalog.corpusCatalog.filter(services.isPresent).map(\.id)
        // In BOAR's language: the ideas are written and tested per language.
        ideaPool = services.suggestions.ideaPool(m?.id, language: Bundle.main.preferredLocalizations.first, installed: installed)
        suggestions = pickIdeas()
        // A may-not-fit note that no longer holds (the model was loaded anyway, or replaced) goes away.
        if let risky = riskyLoad, services.startDecision() != .askRisky(modelId: risky.modelId, onlyModel: risky.onlyModel) {
            riskyLoad = nil
        }
    }

    /// A few of the ideas at random, drawn again for each new chat (android pickIdeas).
    private func pickIdeas() -> [String] {
        Array(ideaPool.shuffled().prefix(Suggestions.ideasShown))
    }

    /// Loads the model when the chat opens, so the first answer doesn't wait for it. Not a model whose last load closed
    /// the app with no other to stand in, nor one that may not fit this device's memory: the chat asks first (StartLoad).
    func preload() {
        guard services.activeModel() != nil || services.backend != .llama, !loadingModel else { return }
        switch services.startDecision() {
        case .askRisky(let id, let only):
            _ = services.loadGuard.consume()
            riskyLoad = RiskyLoad(modelId: id, onlyModel: only)
            return
        case .noFallback(let id, _):
            loadCrash = services.loadGuard.consume() ?? blockedNote(id)
            return
        default: break
        }
        load(held: nil)
    }

    /// Loads the answer model now; then the held question, if any, is sent. A load that returns without a model (not a
    /// closed app) brings the may-not-fit note back, so the user can still choose. `fromNote`: the note's buttons, not the
    /// preload; only then do the questions waiting behind the note start or go (android `userLoad`; `preload` leaves the
    /// queue alone).
    private func load(held: String?, risky: RiskyLoad? = nil, fromNote: Bool = false) {
        loadingModel = true
        let services = services
        Task {
            let loaded = await services.activeSession() != nil
            let crash = services.loadGuard.consume()
            self.loadingModel = false
            self.loadCrash = crash
            if crash != nil || services.backend == .remote { self.refreshModel() }
            if !loaded, crash == nil, let risky { self.riskyLoad = risky }
            // The held question keeps its place: first, before any that waited behind it.
            if loaded, let held { self.send(held, limit: nil, fromQueue: true) }
            // Loaded with nothing held: questions waiting behind the note start now (validator Q-3).
            else if loaded, fromNote { self.runNext() }
            // A failed load: the waiting questions need that model too, so they go with it, said once.
            else if !loaded, fromNote { self.dropOnce(); self.dropQueueWithNote() }
        }
    }

    /// The note for a blocked model with nothing to answer instead: a crash record with no fallback.
    private func blockedNote(_ modelId: String) -> LoadGuard.Crash {
        LoadGuard.Crash(crashedModelId: modelId, crashedLabel: services.catalog.byId(modelId)?.label ?? modelId,
                        fallbackModelId: "", fallbackLabel: "", at: 0)
    }

    /// The note a question gets instead of an answer: the user's model may not fit, or closed the app last time and
    /// nothing can stand in. Nil when it may load, or is already loaded (picked in Models).
    private func gate() async -> (risky: RiskyLoad?, crash: LoadGuard.Crash?)? {
        let id: String
        var note: (risky: RiskyLoad?, crash: LoadGuard.Crash?)
        switch services.startDecision() {
        case .askRisky(let m, let only): (id, note) = (m, (RiskyLoad(modelId: m, onlyModel: only), nil))
        case .noFallback(let m, _): (id, note) = (m, (nil, blockedNote(m)))
        default: return nil
        }
        if let file = services.catalog.byId(id)?.filename, await services.host.residentFilename() == file, services.host.current != nil {
            return nil
        }
        return note
    }

    /// The may-not-fit note's "Load Anyway": loads the model now, and at start from now on without asking.
    func loadAnyway(_ modelId: String) {
        services.rememberLoadAnyway(modelId)
        let risky = riskyLoad
        riskyLoad = nil
        load(held: heldQuestion.take(), risky: risky, fromNote: true)
    }

    /// The crash note's "Try Again with Less Memory": the model is unblocked and loaded now, keeping the mapped file
    /// instead of repacking it (LoadGuard.retryMapped). It answers from then on.
    func retryWithLessMemory(_ modelId: String) {
        services.loadGuard.retryMapped(modelId)
        // The user's call: a model that may not fit isn't asked about again at start.
        if let m = services.catalog.byId(modelId), services.isRisky(m) { services.rememberLoadAnyway(modelId) }
        services.settings.setActiveModelId("llm", modelId)
        loadCrash = nil
        refreshModel()
        guard !loadingModel else { return }
        load(held: heldQuestion.take(), fromNote: true)
    }

    /// The memory note's "Pick Another Model" / "Choose a Model" and its OK: the held question is dropped.
    func dismissLoadNote() {
        heldQuestion = nil
        dropOnce()
        dropQueueWithNote()
        riskyLoad = nil
        loadCrash = nil
    }

    // MARK: sessions

    func newChat() {
        guard job == nil else { return }
        sessionId = nil
        messages = []
        error = nil
        suggestions = pickIdeas()
    }

    func openSession(_ id: String) {
        guard job == nil, id != sessionId else { return }
        Task {
            let records = (try? await services.background { try $0.chats.messages(sessionId: id) }) ?? []
            self.messages = records.map { r in
                let receipt = MessageMeta.receipt(r.meta)
                var item = ChatItem(id: r.id, role: r.role, text: r.text, sources: MessageMeta.sources(r.meta), feedback: r.feedback, receipt: receipt)
                item.staged = MessageMeta.staged(r.meta, receipt: receipt)
                if r.role == "user" { item.step = KeepGoing.step(fromMeta: r.meta) }
                if MessageMeta.error(r.meta) == MessageMeta.interrupted {
                    item.failure = String(localized: "Interrupted: BOAR was closed while answering.")
                }
                return item
            }
            self.sessionId = id
            self.error = nil
        }
    }

    /// Delete with Undo starts (android deleteWithUndo): not the chat still being answered (false); the open one is left at
    /// once, its waiting questions with it, so nothing new lands in a chat about to be deleted.
    func leaveForDelete(_ id: String) -> Bool {
        if job != nil && sessionId == id { return false }
        if sessionId == id {
            flow.clear()
            newChat()
        }
        return true
    }

    /// The chat and its messages; the open one becomes a new chat. Not the chat still being answered.
    func deleteSession(_ id: String) async {
        if job != nil && sessionId == id { return }
        _ = try? await services.background { try $0.chats.deleteSession(sessionId: id) }
        if sessionId == id {
            flow.clear()
            newChat()
        }
        onSessionsChanged?()
    }

    func renameSession(_ id: String, to title: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        _ = try? await services.background { try $0.chats.setTitle(sessionId: id, title: t) }
        onSessionsChanged?()
    }

    func rate(_ messageId: String, _ rating: String) {
        guard let i = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let next = messages[i].feedback == rating ? nil : rating
        messages[i].feedback = next
        // Once, on the first rating: ratings stay on the device and nothing uses them yet.
        if next != nil && !services.settings.ratingNoteShown {
            services.settings.ratingNoteShown = true
            toast = String(localized: "Saved on this \(Platform.deviceNoun) only. Nothing is sent. BOAR doesn't learn from it yet.")
        }
        Task { _ = try? await services.background { try $0.chats.setFeedback(messageId: messageId, rating: next) } }
    }

    // MARK: answering

    /// An answer, a chat title or summary, or a model load still running (FreeMemory waits for them).
    var usesModel: Bool { job != nil || background != nil || loadingModel }

    /// Leaving the screen on iPhone: the answer stops (its text is kept) and a title or summary being written too, as
    /// Metal work isn't allowed in the background.
    ///
    /// Waiting questions go too: nothing may start on the model while the app can't run it (android `stopAll`, Q-1).
    func stopForBackground() {
        stopAll()
        Task { await stopBackground() }
    }

    /// A tap on an instant answer being typed: the rest shows at once (android skipTyping).
    func skipInstantTyping() { skipTyping = true }

    private static var animationsOff: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }

    private static var screenReader: Bool {
        #if canImport(UIKit)
        UIAccessibility.isVoiceOverRunning
        #else
        NSWorkspace.shared.isVoiceOverEnabled
        #endif
    }

    /// Stop ends only the answer in progress, never the queue (validator Q-1). `stopAll` is for the paths that end everything
    /// and then unload, switch or erase.
    func stop() {
        stopFlag.set(true)
        if answeringId != nil { stopping = true }
        services.host.cancel()
    }

    /// Stop and clear the queue: leaving the screen, a tweak, a model removed or switched, an evaluation, the PIN's erase.
    func stopAll() {
        flow.clear()
        stop()
    }

    /// `stopAll`, then waits (up to `timeout`) for the answer, a title or summary and a load to end (android
    /// `BoarServices.stopAnswersAndWait`); false when something still uses the model.
    func stopAllAndWait(timeout: Duration = .seconds(15)) async -> Bool {
        stopAll()
        let clock = ContinuousClock()
        let until = clock.now + timeout
        // A title or summary counts too (android's busy check), also one that starts during the wait: an answer already past
        // its stop check ends as not stopped and writes a title after it.
        while usesModel && clock.now < until {
            if background != nil { await stopBackground() } else { try? await Task.sleep(for: .milliseconds(100)) }
        }
        return !usesModel
    }

    // MARK: the queue

    func removeQueued(_ id: Int64) { flow.remove(id) }

    func clearQueue() { flow.clear() }

    /// The waiting questions become one, answered together. A safety question (the CO card) stays its own turn, ahead of
    /// the merged one, whether Cohazard is on or not.
    func mergeQueue() { flow.merge { LabTools.coHazard($0) != nil } }

    /// A memory note (may not fit, closed the app) is on screen.
    var noteUp: Bool { riskyLoad != nil || loadCrash != nil }

    /// Starts the oldest waiting question, if any.
    private func runNext() {
        guard let next = flow.takeNext(running: job != nil) else { return }
        send(next, limit: nil, fromQueue: true)
    }

    /// The load note closed, or the model didn't load: the waiting questions need that model too, so they go, said once.
    private func dropQueueWithNote() {
        if let n = flow.dropWithNote() { toast = String(localized: "\(n) waiting questions were dropped: they need that model too.") }
    }

    /// `limit` overrides the answer's token limit (the "Allow more and redo" note); nil uses the setting.
    func send(_ query: String, limit: Int? = nil) {
        send(query, limit: limit, fromQueue: false)
    }

    /// While BOAR answers, a question waits its turn (PromptQueue, up to 5) and runs after, as the chat's next turn.
    /// `fromQueue`: the queue starting it (it doesn't join the queue again).
    private func send(_ query: String, limit: Int?, fromQueue: Bool) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // Everything here runs on the main actor, so no question can land between an answer's end and the next waiting
        // question's start: `job` clears and `runNext` follows with no suspension between (android's `handoff`, Q-2).
        switch flow.admit(q, running: job != nil, fromQueue: fromQueue, behindNote: heldQuestion != nil && noteUp, noteUp: noteUp) {
        case .start:
            break
        case .queued(let startNow):
            if startNow { runNext() }
            return
        case .full(let startNow):
            toast = String(localized: "Up to 5 questions can wait. Send this one when one of them has run.")
            if startNow { runNext() }
            return
        }
        stopFlag.set(false)
        job = Task {
            // A model that may not fit, or closed the app with nothing to stand in, isn't loaded for a question: the
            // question waits for the user's choice in the note.
            if let note = await self.gate() {
                self.heldQuestion = q
                self.riskyLoad = note.risky
                if let crash = note.crash { self.loadCrash = crash }
                self.job = nil
                return
            }
            if await self.holdForPrune(q, limit: limit) {
                self.job = nil
                return
            }
            self.pruneAccepted = false
            await self.answer(q, limit: limit)
            // However the answer ended (done, stopped, failed), the next waiting question starts.
            self.job = nil
            self.runNext()
        }
    }

    /// The first question of a new chat under a limit: the dialog names the oldest chat before it goes (android rc3).
    private func holdForPrune(_ q: String, limit: Int?) async -> Bool {
        guard sessionId == nil, !pruneAccepted, pruneNote == nil else { return false }
        let max = services.settings.maxSavedSessions
        let going = (try? await services.background { try $0.chats.pushedOutByNew(maxSessions: max) }) ?? []
        guard let first = going.first else { return false }
        prunedQuestion = PrunedQuestion(text: q, limit: limit)
        pruneNote = PruneNote(title: first.title, more: going.count - 1, max: max)
        return true
    }

    /// The prune note's "Keep All Chats": nothing is deleted, now or later; the question goes.
    func pruneKeepAll() {
        services.settings.maxSavedSessions = AppSettings.keepAllChats
        resumePruned()
    }

    /// The prune note's "Delete It": the question goes, and the oldest chat with it after the answer, as before.
    func pruneDelete() {
        pruneAccepted = true
        resumePruned()
    }

    /// The prune note closed: the question is dropped, unasked.
    func pruneCancel() {
        // The alert also reports "closed" after Keep All or Delete It already took the question: nothing to drop then.
        guard pruneNote != nil else { return }
        prunedQuestion = nil
        dropOnce()
        pruneNote = nil
    }

    private func resumePruned() {
        let held = prunedQuestion
        prunedQuestion = nil
        pruneNote = nil
        if let held { send(held.text, limit: held.limit) } else { pruneAccepted = false }
    }

    /// Asks `answerId`'s question again with a higher token limit, for this answer only (the setting stays as it is).
    func redo(_ answerId: String, limit: Int) {
        guard job == nil, let q = question(for: answerId) else { return }
        send(q, limit: limit)
    }

    /// "Ask BOAR instead": the question of a Labs tool's answer again, with the Labs tools skipped so the model answers.
    func askModel(_ answerId: String) {
        // Not queued: the "skip the Labs tools" flag belongs to this question only, so not while others wait either (it
        // would be taken by the next one in line).
        guard job == nil, flow.isEmpty, !noteUp, let q = question(for: answerId) else { return }
        once.skipTools = true
        send(q)
    }

    /// What the next question carries, for that question only: the Labs tools skipped (`askModel`), and a Keep going step's
    /// style, Deep Research and verb. The user's style and the Deep Research switch are never written.
    @ObservationIgnored private var once = KeepGoing.Overrides()

    /// The held question went with its note (closed, the catalog opened instead, or the model didn't load): what was set for
    /// it goes too, or the next typed question would run in Detailed or Deep Research, skip the Labs tools and show a
    /// step's verb (android `dropOnce`, validator A-2). iOS has no bypassed-plugin context to clear (`AskModelContext`).
    private func dropOnce() { once.drop() }

    /// A Keep going step under `answerId`: the same question again, for that answer only. Go deeper in Detailed, Research
    /// this with Deep Research, Ask BOAR as `askModel`. Continue is its own message ("Continue" / "Continuar"), a meta
    /// follow-up in the same style, with no step mark: the bubble shows what was sent. Not while BOAR answers, questions
    /// wait or a note is up (the bubbles hide then).
    func keepGoing(_ answerId: String, _ step: KeepGoing.Step) {
        guard job == nil, flow.isEmpty, !noteUp, let q = question(for: answerId) else { return }
        if step == .continue {
            send(String(localized: "Continue"))
            return
        }
        once = .of(step)
        switch step {
        case .deeper, .research: send(q)
        case .ask: askModel(answerId)
        case .continue: break
        }
    }

    /// The question an answer replied to (the user message just before it).
    func question(for answerId: String) -> String? {
        guard let i = messages.firstIndex(where: { $0.id == answerId }), i > 0, messages[i - 1].isUser else { return nil }
        return messages[i - 1].text
    }

    /// Try Again on a failed answer: the failed row goes away and the same question is answered again, under the same
    /// saved question (a failed answer with no text was never saved). An answer with others after it (an interrupted one
    /// in the middle of the chat) is asked again at the end instead, as on Android, and stays: a new answer can't take
    /// its place, it would land after the later ones.
    func retry(_ answerId: String) {
        guard job == nil, let i = messages.firstIndex(where: { $0.id == answerId }), i > 0, messages[i - 1].isUser else { return }
        let question = messages[i - 1]
        guard i == messages.count - 1 else {
            send(question.text)
            return
        }
        messages.remove(at: i)
        stopFlag.set(false)
        // The saved question keeps its step mark, so it's answered the way the bubble says (Detailed, Deep Research, the
        // Labs tools skipped): what the step set was taken by the first try. Android asks again as a new message instead.
        once = question.step.map(KeepGoing.Overrides.of) ?? KeepGoing.Overrides()
        let services = services
        job = Task {
            // An answer BOAR was closed in the middle of is saved: the new one replaces it.
            _ = try? await services.background { try $0.chats.deleteMessage(id: answerId) }
            await self.answer(question.text, savedQuestionId: question.id)
            self.job = nil
            self.runNext()
        }
    }

    /// Records what the answer is doing now, as the status line and as a step of the answer (a new step only when the
    /// kind changes; a new sub-question updates the current one).
    private func enter(_ a: ChatActivity, answerId: String) {
        activity = a
        guard let i = messages.lastIndex(where: { $0.id == answerId }) else { return }
        var step = AnswerStep(kind: a.stepKind, startedAt: .now)
        if case .researching(_, let index, let count) = a { step.index = index; step.count = count }
        if let last = messages[i].steps.last, last.kind == step.kind {
            if last.index != step.index { messages[i].steps[messages[i].steps.count - 1].index = step.index }
            if last.count != step.count { messages[i].steps[messages[i].steps.count - 1].count = step.count }
        } else {
            messages[i].steps.append(step)
        }
    }

    /// What a Deep Research, recap or adaptive answer hands back to the chat.
    private struct Outcome: Sendable {
        var sources: [Chunk]
        var timedOut: Bool
        var metrics: GenerationMetrics?
        var fromPreviousAnswer = false
    }

    /// A message about the conversation itself, answered from it without a search: "summarize our conversation", or
    /// "TL;DR" / "a summary please" after an answer. "continue" keeps the search: it asks for more than the chat holds.
    nonisolated static func aboutConversation(_ query: String, _ history: ConversationHistory, _ conversation: [DeepResearch.Exchange]) -> Bool {
        (DeepResearch.isConversationRecap(query)
            && conversation.contains { !DeepResearch.isConversationRecap($0.question) && !DeepResearch.isSummaryFollowUp($0.question) })
            || (DeepResearch.isSummaryFollowUp(query) && DeepResearch.lastAnswered(query, history) != nil)
    }

    private enum Event: Sendable {
        case piece(String)
        case activity(ChatActivity)
        /// Adaptive routing's generate step runs on a model other than the answering one (android `answeringModel`).
        case routed(String?)
    }

    private func answer(_ q: String, savedQuestionId: String? = nil, limit: Int? = nil) async {
        // What this question carries is taken before anything can wait (android `send` reads each once and clears it).
        let carried = once.take()
        await stopBackground()
        let services = services
        let settings = services.settings
        let isNewSession = sessionId == nil
        let prior = messages.filter { !$0.text.isEmpty && $0.id != savedQuestionId }
        let sid: String
        do {
            if let open = sessionId {
                sid = open
            } else {
                // The question stands in as the title until the model writes one.
                sid = try await services.background { s in
                    let created = try s.chats.createSession()
                    try s.chats.setTitle(sessionId: created.id, title: String(q.prefix(60)))
                    return created.id
                }
            }
        } catch {
            self.error = error.localizedDescription
            return
        }
        let userId = savedQuestionId ?? services.chats.newId()
        let answerId = services.chats.newId()
        // The answer is saved as it's written, marked interrupted until it ends: if iOS closes BOAR mid-answer, the chat
        // reopens with what was written and the note, not a lost answer (android ChatViewModel.savePartial).
        let interruptedMeta = MessageMeta.encode([], nil, error: MessageMeta.interrupted)
        _ = try? await services.background { s in
            if savedQuestionId == nil {
                try s.chats.addMessage(sessionId: sid, role: "user", text: q, id: userId)
                if let step = carried.step { try s.chats.setMessageMeta(messageId: userId, meta: KeepGoing.stepMeta(step)) }
            }
            try s.chats.upsertMessage(sessionId: sid, role: "assistant", text: "", id: answerId)
            try s.chats.setMessageMeta(messageId: answerId, meta: interruptedMeta)
        }
        sessionId = sid
        error = nil
        answeringId = answerId
        activity = nil
        liveTokPerSec = nil
        if savedQuestionId == nil { messages.append(ChatItem(id: userId, role: "user", text: q, step: carried.step)) }
        messages.append(ChatItem(id: answerId, role: "assistant", text: ""))
        if isNewSession { onSessionsChanged?() }

        // The app's language is the answer's last word when the question can't tell (AnswerLanguage, t9 0420).
        AnswerLanguage.appLanguage = settings.languageId
        let chosenStyle = carried.style ?? settings.personalityId ?? services.personalities.defaultId
        // Personal Files: only the user's own files, whole; no Deep Research, router or recap of the library.
        let personal = PersonalFiles.isOn(chosenStyle)
        // A small answer model (the 1.5B) gets Detailed without D4's "Always do what the user asks" (r4to, Oct 18).
        let smallModel = (services.answerModel()?.sizeBytes ?? .max) < Personalities.smallModelBytes
        // Health and seed-phrase questions answer in Succinct even under Detailed: a padded detail there can hurt (r4to's
        // audits: 20 % of Detailed's first-aid claims wrong). A follow-up in such a chat too ("and for how long?").
        let shortReason = ShortAnswer.reason(chosenStyle: chosenStyle, question: q, previousQuestion: prior.last { $0.isUser }?.text)
        // Personal Files keeps its files-only prompt: kept short by a reminder instead.
        let style = shortReason != nil && !personal ? "succinct" : chosenStyle
        let (systemPrompt, baseReminder) = services.personalities.promptFor(style, customPrompt: settings.customSystemPrompt, smallModel: smallModel)
        // A Personal Files summary: in the model's words, each result with the mark the code gave it (LabRanges).
        let ptQ = AnswerLanguage.of(q) == .pt
        let summaryLine = personal && PersonalFiles.asksSummary(q) ? (ptQ ? PersonalFiles.summaryPT : PersonalFiles.summaryEN) : nil
        let reminderParts = [baseReminder, personal && shortReason != nil ? ShortAnswer.personalShort : nil, summaryLine].compactMap { $0 }
        let joinedReminder = reminderParts.joined(separator: " ")
        let styleReminder: String? = joinedReminder.allSatisfy(\.isWhitespace) ? nil : joinedReminder
        // The answer a meta follow-up ("summary", "continue") is written from: the last one with text.
        let lastAnswer = prior.last { !$0.isUser && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // Every answered question so far, oldest first: what "summarize our conversation" is written from.
        let conversation = zip(prior, prior.dropFirst()).compactMap { u, a -> DeepResearch.Exchange? in
            u.isUser && !a.isUser && !a.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? DeepResearch.Exchange(question: u.text, answer: AnswerText.stripThinking(a.text)) : nil
        }
        let summary = try? await services.background { try $0.chats.listSessions().first { $0.id == sid }?.summary }
        // Within a token budget: earlier answers cut to their opening sentences (HistoryBudget).
        let turns = prior.suffix(Self.verbatimMessageCount).map { ConversationTurn(role: $0.role, text: $0.isUser ? $0.text : AnswerText.stripThinking($0.text)) }
        let history = ConversationHistory(summary: summary ?? nil, turns: HistoryBudget.budget(Array(turns)))
        let tweaks = settings.engineTweaks
        // Small talk never starts a Deep Research or the router: "hi" took minutes on a big model (AnswerPath).
        let smallTalk = AnswerPath.isSmallTalk(q)
        let aboutConversation = Self.aboutConversation(q, history, conversation)
        // Deep Research for this question: the switch, or a Keep going step's (the switch itself stays as set).
        let deepOn = carried.deep ?? deepResearch
        let way = AnswerPath.of(
            deepResearch: deepOn && !personal, aboutConversation: aboutConversation,
            adaptive: !personal && settings.adaptiveRoutingEnabled, smallTalk: smallTalk
        )
        // The tool slot (Boar Labs): an instant answer needs no model, a context is read by it. Not for a recap; under
        // Deep Research or Personal Files only a safety answer (Boar Cohazard).
        let deep = deepOn && !personal
        let skipTools = carried.skipTools
        // A merged queue goes to the model whole: an instant answer would take one question and drop the rest (validator Q-8).
        let tool = skipTools || aboutConversation ? nil : AnswerTools.run(
            Labs.shared.activeTools, query: q,
            history: prior.map { ConversationTurn(role: $0.role, text: $0.isUser ? $0.text : AnswerText.stripThinking($0.text)) }
        ).flatMap { !(deep || personal) || PersonalFiles.keepsTool($0.tool) ? $0 : nil }
            .flatMap { PromptMerge.forModel($0, question: q) }
        let instant = tool?.instantText
        let toolPrompt = AnswerTools.systemPrompt(systemPrompt, tool)
        // Boar Staged answers (android AnswerModes.staged): the default path only. It loads the model itself, after the
        // search, so the sources show while a cold model loads.
        let staged = StagedChat.chooses(enabled: settings.stagedQuotes, instant: instant != nil, personal: personal, deepResearch: deep,
                                        aboutConversation: aboutConversation, smallTalk: smallTalk)
        // How this answer is written (android Receipt.path), for the check slot and the receipt: Deep Research and recaps
        // are not checked, and a Deep Research answer keeps its border in the history.
        let path: String? = switch way {
        case _ where instant != nil: nil
        case _ where staged: "staged"
        case .research: "deep"
        case .recap: "chat"
        case .adaptive: "adaptive"
        case .pipeline: nil
        }

        let clock = ContinuousClock()
        let startAt = clock.now
        var firstAt: ContinuousClock.Instant?
        var tokens = 0
        var text = ""
        var sources: [Chunk] = []
        var metrics: GenerationMetrics?
        var retrievalMs: Double?
        var timedOut = false
        var loadMs: Double?
        var failure: Error?
        /// Written from the last answer: its numbers [n] are that answer's sources.
        var reusedSources: [ChatSource]?
        /// Reasoning models: when the reasoning started, and whether it is still to be checked for.
        var thinkingAt: ContinuousClock.Instant?
        var thinkingOpen = true
        /// The limit the answer could hit, set once the model is loaded (an instant answer has none), and the context it
        /// was opened with.
        var limited: Int?
        var openedContext: Int?
        /// Staged: what the card shows and when each step happened (kept with the answer).
        var stagedView: StagedView?
        var stagedTimes: [String: Double]?
        // A user's file with results and ranges gets each one marked in code, given to the model with the passage (the
        // 1.7B read 231 against "below 190" as fine).
        let annotateRanges: @Sendable (Chunk) -> Chunk = { c in
            guard c.collectionId != nil, let n = LabRanges.note(c.body, pt: ptQ) else { return c }
            var marked = c
            marked.body = c.body + "\n\n" + n
            return marked
        }

        let mark = BoarPerf.begin("answer", way.rawValue)

        /// The partial answer's saves, every few seconds, one after the other; the final save waits for them.
        var partialSave: Task<Void, Never>?
        /// When the instant answer was ready, before it was typed: the receipt's time (android instantAt).
        var instantAt: ContinuousClock.Instant?
        var savedAt = clock.now

        /// One streamed piece; `whole`: the text as it reads now (a staged answer joins its intro and details), instead of
        /// the piece appended.
        func onPiece(_ piece: String, whole: String? = nil) {
            tokens += 1
            let now = clock.now
            if firstAt == nil {
                firstAt = now
                BoarPerf.event("answer.firstToken")
            }
            text = whole ?? text + piece
            if savedAt.duration(to: now) > Self.partialSaveEvery {
                savedAt = now
                let partial = text
                partialSave = Task { [previous = partialSave] in
                    await previous?.value
                    _ = try? await services.background { try $0.chats.upsertMessage(sessionId: sid, role: "assistant", text: partial, id: answerId) }
                }
            }
            let elapsed = Self.seconds(firstAt!.duration(to: now))
            if elapsed > 0.5 { liveTokPerSec = Double(tokens) / elapsed }
            guard let i = messages.lastIndex(where: { $0.id == answerId }) else { return }
            messages[i].text = text
            // The reasoning of a thinking model is a thinking step; the answer after it is writing.
            if thinkingOpen {
                let split = AnswerText.splitThinking(text)
                if split.thinkingInProgress {
                    if thinkingAt == nil { thinkingAt = now }
                    if activity?.stepKind != .thinking { enter(.thinking, answerId: answerId) }
                    return
                }
                thinkingOpen = false
                if split.thinking != nil {
                    messages[i].thinkingSeconds = Self.seconds((thinkingAt ?? firstAt!).duration(to: now))
                }
            }
            if activity?.stepKind != .writing { enter(.generating, answerId: answerId) }
        }

        /// Boar Staged answers (android ChatViewModel's staged path): the sources first, a short intro, the details; the
        /// engine loads the model itself, after the cards. Stop keeps what is shown.
        func runStaged() async throws {
            let stop = stopFlag
            var view = StagedView(withPassages: shortReason != nil)
            var intro = ""
            var details = ""
            var afterLoadNoted = false
            func show(_ event: StagedEvent, sources shown: [ChatSource]? = nil) {
                view.apply(event, query: q)
                stagedView = view
                guard let i = messages.lastIndex(where: { $0.id == answerId }) else { return }
                messages[i].staged = view
                if let shown {
                    messages[i].sources = shown
                    messages[i].sourceCount = shown.count
                }
            }
            /// Known once the model is open: what the load took, and the context Auto fits the length to.
            func afterLoad() {
                guard !afterLoadNoted else { return }
                afterLoadNoted = true
                loadMs = services.host.lastLoadMs
                openedContext = services.host.openedContext
                limited = limit ?? settings.answerTokens(openedContext: openedContext)
            }
            let budget = limit ?? settings.answerTokens(openedContext: services.host.openedContext)
            limited = budget
            let succinct = services.personalities.promptFor("succinct", customPrompt: nil, smallModel: smallModel).styleReminder
            let picked = services.personalities.promptFor(style, customPrompt: settings.customSystemPrompt, smallModel: smallModel).styleReminder
            let reminders = StagedChat.reminders(style: style, succinct: succinct, picked: picked)
            let request = StagedRequest(query: q, systemPrompt: toolPrompt, introReminder: reminders.intro, detailsReminder: reminders.details,
                                        maxTokens: budget, history: history, enableThinking: tweaks.thinkingEnabled)
            let engine = StagedAnswer(retriever: services.retriever, stages: Labs.shared.activeSearchStages, annotate: annotateRanges)
            for try await e in engine.answer(request, load: { await services.activeSession() }, shouldStop: { stop.value }) {
                switch e {
                case .step(let step):
                    show(e)
                    if stopping { break }
                    if step == .sources {
                        enter(.retrieving, answerId: answerId)
                    } else if text.isEmpty {
                        // The model loads right after this step starts.
                        enter(step == .intro && services.host.current == nil ? .loadingModel : .thinking, answerId: answerId)
                    }
                case .cards(let chunks, _, let ms):
                    sources = chunks
                    retrievalMs = ms
                    // Numbered as in the prompt, so a [n] tapped while the answer streams opens its source; grouped at the end.
                    show(e, sources: Self.numberedSources(chunks))
                case .piece(let step, let piece):
                    afterLoad()
                    // The intro and the details kept apart and shown joined, as they're saved: one paragraph break between
                    // them, not one per piece (one token per line, X6, Nov 9).
                    if step == .details { details += piece } else { intro += piece }
                    onPiece(piece, whole: StagedAnswer.join(intro, details))
                case .restart:
                    intro = ""
                    details = ""
                    text = ""
                    thinkingOpen = true
                    thinkingAt = nil
                    if let i = messages.lastIndex(where: { $0.id == answerId }) { messages[i].text = "" }
                case .moreSources(let added):
                    sources += added
                    show(e, sources: Self.numberedSources(sources))
                case .checked:
                    show(e)
                case .done(let d):
                    afterLoad()
                    sources = d.sources
                    metrics = d.metrics
                    stagedTimes = d.times.toMap()
                    // The saved text: the intro, then the details, thinking left out.
                    text = d.text
                    show(e)
                    if let i = messages.lastIndex(where: { $0.id == answerId }) { messages[i].text = text }
                    if d.noModel {
                        if services.backend == .remote {
                            throw ChatError.remoteUnreachable(services.host.lastRemoteError ?? String(localized: "Add the Mac's address in Settings → Advanced → Engine."))
                        }
                        noModel = true
                        throw ChatError.noModel
                    }
                }
            }
        }

        do {
            if let instant {
                // An instant answer doesn't load the model.
                // Shown at typing speed (android InstantTyping), presentation only: a tap or Stop shows the rest at once (the
                // answer is already whole); the safety answer, Reduce Motion and VoiceOver show it at once. The receipt keeps
                // the time of the answer, not of the typing.
                instantAt = clock.now
                if InstantTyping.typed(tool: tool?.tool ?? "", animationsOff: Self.animationsOff, screenReader: Self.screenReader) {
                    skipTyping = false
                    var shownLen = 0
                    for piece in InstantTyping.pieces(instant) {
                        if skipTyping || stopFlag.value {
                            onPiece(String(instant.dropFirst(shownLen)))
                            shownLen = instant.count
                            break
                        }
                        onPiece(piece)
                        shownLen += piece.count
                        try? await clock.sleep(for: .milliseconds(InstantTyping.stepMs))
                    }
                    if shownLen < instant.count { onPiece(String(instant.dropFirst(shownLen))) }
                    skipTyping = false
                } else {
                    onPiece(instant)
                }
                throw InstantAnswer()
            }
            if staged {
                try await runStaged()
                throw StagedAnswerRan()
            }
            if services.host.current == nil { enter(.loadingModel, answerId: answerId) }
            guard let session = await services.activeSession() else {
                if services.backend == .remote {
                    throw ChatError.remoteUnreachable(services.host.lastRemoteError ?? String(localized: "Add the Mac's address in Settings → Advanced → Engine."))
                }
                noModel = true
                throw ChatError.noModel
            }
            loadMs = services.host.lastLoadMs
            openedContext = session.capabilities.contextTokens ?? services.host.openedContext
            var maxTokens = limit ?? settings.answerTokens(openedContext: openedContext)
            // A thank-you or greeting: Succinct's length in any style.
            if smallTalk { maxTokens = min(maxTokens, AppSettings.defaultMaxTokens) }
            limited = maxTokens
            // The search stages of the labs switched on now (Facts' country figures): every answer path searches through them.
            let searchStages = Labs.shared.activeSearchStages
            if way != .pipeline {
                let (events, sink) = AsyncStream<Event>.makeStream()
                let stop = stopFlag
                let previousAnswer = lastAnswer.map { AnswerText.stripThinking($0.text) }
                // The write-up in the question's language (t9 0420): DeepResearch had the slot, nothing filled it.
                let answerLanguage = AnswerLanguage.line(
                    AnswerLanguage.of(q, earlier: prior.filter(\.isUser).map(\.text)), withSources: way == .research
                )
                let work = Task.detached { () throws -> Outcome in
                    defer { sink.finish() }
                    if way == .research || way == .recap {
                        let research = way == .research
                        let r = try await DeepResearch(generator: SessionEngine(session, enableThinking: tweaks.thinkingEnabled), retriever: services.retriever, tweaks: tweaks, stages: searchStages)
                            .run(q, systemPrompt: systemPrompt, history: history, maxTokens: maxTokens,
                                 onProgress: { p in
                                     sink.yield(.activity(research
                                         ? .researching(p.stage, index: p.subQuestionIndex.map { $0 + 1 }, count: p.subQuestionCount) : .thinking))
                                 },
                                 onToken: { sink.yield(.piece($0)) }, shouldStop: { stop.value }, answerLanguage: answerLanguage,
                                 previousAnswer: previousAnswer, conversation: conversation)
                        return Outcome(sources: r.citations, timedOut: r.timedOut, metrics: r.metrics, fromPreviousAnswer: r.fromPreviousAnswer)
                    }
                    let (chunks, timedOut) = try await Self.adaptive(q, systemPrompt: toolPrompt, styleReminder: styleReminder, history: history,
                                                                      maxTokens: maxTokens, services: services, stages: searchStages, stop: stop, sink: sink)
                    return Outcome(sources: chunks, timedOut: timedOut)
                }
                for await e in events {
                    switch e {
                    case .piece(let p): onPiece(p)
                    case .activity(let a): if firstAt == nil { enter(a, answerId: answerId) }
                    case .routed(let name): answeringModel = name
                    }
                }
                let outcome = try await work.value
                (sources, timedOut) = (outcome.sources, outcome.timedOut)
                if outcome.metrics != nil { metrics = outcome.metrics }
                if outcome.fromPreviousAnswer { reusedSources = lastAnswer?.sources }
            } else {
                let pipeline = AnswerPipeline(
                    session: session, retriever: services.retriever, params: personal ? PersonalFiles.retrieval() : .default,
                    stages: searchStages,
                    annotate: annotateRanges
                )
                var request = AnswerRequest(query: q, systemPrompt: toolPrompt, styleReminder: styleReminder, maxTokens: maxTokens,
                                            history: history, enableThinking: tweaks.thinkingEnabled)
                if personal {
                    // Nothing found in the files: the fixed line, then where to switch a collection on when none is on, or
                    // how to ask when one is. The prompt lists the switched-on files by name.
                    let ownFiles = (try? await services.background { try $0.retriever.ownFiles() }) ?? []
                    let hint = ownFiles.isEmpty
                        ? String(localized: "Check that the collection is switched on in Knowledge → Personal Files.")
                        : String(localized: "Try asking about something your files say, in their words, or ask for a summary of your files.")
                    request = PersonalFiles.request(
                        request, contextSize: openedContext ?? EngineTweaks.contextSizeForRam(services.totalRamBytes),
                        notFound: String(localized: "I couldn't find this in your Personal Files.") + "\n\n" + hint,
                        filesNote: OwnFiles.note(ownFiles)
                    )
                }
                for try await e in pipeline.answer(request) {
                    switch e {
                    case .stage(let s):
                        // The writing step starts with the first word (onPiece), after any reasoning.
                        if !stopping && s != .generating { enter(s == .retrieving ? .retrieving : .thinking, answerId: answerId) }
                    case .sources(let chunks, _, _, _):
                        sources = chunks
                        // Numbered now, so the citations are tappable while the answer streams.
                        if let i = messages.lastIndex(where: { $0.id == answerId }) {
                            messages[i].sources = Self.numberedSources(chunks)
                            messages[i].sourceCount = chunks.count
                        }
                    case .piece(let p): onPiece(p)
                    case .done(let r):
                        metrics = r.metrics
                        retrievalMs = r.retrievalMs
                    }
                }
            }
        } catch is CancellationError {
        } catch is InstantAnswer {
        } catch is StagedAnswerRan {
        } catch {
            failure = error
        }
        // Ended without a word, no error and not stopped: say so (with Try Again) instead of an empty answer.
        if failure == nil, !stopFlag.value, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failure = ChatError.emptyAnswer
        }

        mark.end("\(tokens) tokens\(failure == nil ? "" : ", failed")")
        // One source per article, best first; the answer's numbers follow (a reused list is already grouped).
        let grouped = Self.groupSources(sources)
        if reusedSources == nil { text = SourceGroups.renumber(text, map: grouped.renumber) }
        // A model that opens with the not-found line and then answers from the files keeps only the answer.
        if personal {
            let kept = PersonalFiles.dropHedge(text)
            if kept != text { text = kept }
        }
        let shown = reusedSources ?? grouped.items
        let stopped = stopFlag.value
        // The check slot (Boar Labs): a model's finished answer on the default or adaptive path may be repaired; not one
        // that was stopped, timed out or failed part way, nor one from the user's own files.
        let repair = skipTools || personal || !LabTools.checksAnswer(instant: instant != nil, stopped: stopped, timedOut: timedOut, failed: failure != nil,
                                                         path: path, blank: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? nil : AnswerChecks.run(Labs.shared.activeChecks, question: q, answer: text)
        if let repair { text = repair.text }
        let toolCodes = [tool?.tool, repair?.tool].compactMap { $0 }.joined(separator: "+")
        // The style the answer was written in, kept in the receipt (android: Personal Files stays "personal").
        let receiptStyle = shortReason != nil && !personal ? "succinct" : chosenStyle
        var receipt: Receipt?
        if instant != nil, let firstAt {
            // An instant answer generated nothing: its receipt has the time and the tool, no speed.
            receipt = Receipt(totalMs: Self.seconds(startAt.duration(to: instantAt ?? clock.now)) * 1000, ttftMs: Self.seconds(startAt.duration(to: firstAt)) * 1000,
                              tokPerSec: 0, tokens: 0, model: nil, retrievalMs: nil, prefillMs: nil, contextTokens: nil, loadMs: nil,
                              styleNote: nil, tool: toolCodes, path: path, style: receiptStyle)
        } else if let firstAt, tokens > 0 {
            let end = clock.now
            let wallRate = Double(tokens) / max(Self.seconds(firstAt.duration(to: end)), 1e-3)
            let decodeRate = metrics?.decodeTokPerSec ?? 0
            receipt = Receipt(
                totalMs: Self.seconds(startAt.duration(to: end)) * 1000, ttftMs: Self.seconds(startAt.duration(to: firstAt)) * 1000,
                tokPerSec: decodeRate > 0 ? decodeRate : wallRate, tokens: (metrics?.generatedTokens ?? 0) > 0 ? metrics!.generatedTokens : tokens,
                model: modelLabel, retrievalMs: retrievalMs, prefillMs: metrics?.prefillMs, contextTokens: metrics?.promptTokens, loadMs: loadMs,
                styleNote: shortReason == ShortAnswer.smallTalk ? nil : shortReason, tool: toolCodes.isEmpty ? nil : toolCodes,
                path: path, style: receiptStyle, stages: stagedTimes)
        }
        // Ended at its token limit rather than by itself: a note, and a redo at the next length that fits.
        let generated = (metrics?.generatedTokens ?? 0) > 0 ? metrics!.generatedTokens : tokens
        let cutAt = limited.flatMap { l in
            !stopped && !timedOut && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && AnswerLimit.reached(generated: generated, limit: l) ? l : nil
        }
        let nextLimit = cutAt.flatMap { AnswerLimit.next(after: $0, options: services.personalities.maxTokensOptions, openedContext: openedContext) }
        let finalText = text
        // Written over the interrupted mark, which an answer that ended no longer has.
        stagedView?.step = nil
        let meta = MessageMeta.encode(shown, receipt, staged: stagedView)
        let maxSessions = settings.maxSavedSessions
        // A failed answer with no text stays on screen (with Try Again) but is not saved.
        let keep = failure == nil || !finalText.isEmpty
        await partialSave?.value
        let saved = (try? await services.background { s -> Bool in
            if keep {
                try s.chats.upsertMessage(sessionId: sid, role: "assistant", text: finalText, id: answerId)
                try s.chats.setMessageMeta(messageId: answerId, meta: meta)
            } else {
                try s.chats.deleteMessage(id: answerId)
            }
            try s.chats.prune(maxSessions: maxSessions)
            return keep
        }) ?? false
        // Boar Avatars: a saved answer that wrote something; Boar Polyglot's "doesn't speak it yet" reply isn't one. The
        // speed avatars count this device's speed: an answer from the Mac on the network (iOS only) gives none.
        if saved && !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tool?.tool != LanguageGate.tool {
            let speed = instant == nil && services.backend != .remote ? receipt?.tokPerSec : nil
            services.vault.answered(sourced: !shown.isEmpty, deep: deep, portuguese: PtLexicon.looksPortuguese(q),
                                    tokPerSec: speed, newChat: isNewSession)
        }
        if let i = messages.lastIndex(where: { $0.id == answerId }) {
            messages[i].text = finalText
            messages[i].sources = shown
            if messages[i].steps.contains(where: { $0.kind == .searching }) { messages[i].sourceCount = shown.count }
            messages[i].stopped = stopped
            messages[i].timedOut = timedOut
            messages[i].cutAt = cutAt
            messages[i].nextLimit = nextLimit
            messages[i].receipt = receipt
            messages[i].staged = stagedView
            messages[i].answerSeconds = Self.seconds(startAt.duration(to: clock.now))
            if let failure {
                messages[i].failureNoModel = { if case ChatError.noModel = failure { true } else { false } }()
                messages[i].failure = messages[i].failureNoModel
                    ? String(localized: "No answer model is installed. Download one in Models.")
                    : failure.localizedDescription
            }
        }
        answeringId = nil
        answeringModel = nil
        activity = nil
        stopping = false
        let all = prior + [ChatItem(id: userId, role: "user", text: q), ChatItem(id: answerId, role: "assistant", text: finalText)]
        if keep {
            afterAnswer(sessionId: sid, isNewSession: isNewSession, stopped: stopped, all: all, systemPrompt: systemPrompt, hadSources: !sources.isEmpty, filesOnly: personal)
        }
        onSessionsChanged?()
    }

    /// The sources as the prompt numbers them, from 1: what the answer's [n] point at while it streams.
    private static func numberedSources(_ sources: [Chunk]) -> [ChatSource] {
        sources.enumerated().map { ChatSource(number: $0.offset + 1, chunk: $0.element) }
    }

    /// One source per article, best first, numbered from 1; `renumber` maps the answer's old [n] to the new ones.
    private static func groupSources(_ sources: [Chunk]) -> (items: [ChatSource], renumber: [Int: Int]) {
        let grouped = SourceGroups.group(sources.map { ChatSource(number: 0, chunk: $0) },
                                         key: { SourceGroups.articleKey(source: $0.source, docId: $0.docId, title: $0.title) },
                                         score: { $0.similarity ?? $0.relevance }) { g in
            var first = g[0]
            first.similarity = g.compactMap(\.similarity).max()
            first.relevance = g.compactMap(\.relevance).max()
            first.body = g.map(\.body).joined(separator: "\n…\n")
            return first
        }
        let items = grouped.items.enumerated().map { i, s in
            var s = s
            s.number = i + 1
            return s
        }
        return (items, grouped.renumber)
    }

    /// runAdaptiveChat: plan with the installed models and the user's routing settings, then execute.
    nonisolated private static func adaptive(
        _ q: String, systemPrompt: String, styleReminder: String?, history: ConversationHistory, maxTokens: Int,
        services: BoarServices, stages: [any SearchStage], stop: StopFlag, sink: AsyncStream<Event>.Continuation
    ) async throws -> ([Chunk], Bool) {
        let s = services.settings
        let statuses = services.catalog.models.filter { $0.kind == .llm }.map { m in
            Profiles.AvailableModel(RoutableModel(id: m.id, isLanguageModel: true, sizeBytes: m.sizeBytes, roles: m.capabilities?.roles,
                                                  estimatedMemoryMb: m.capabilities?.estimatedMemoryMb,
                                                  estimatedTokensPerSecond: m.capabilities?.estimatedTokensPerSecond),
                                    present: services.isInstalled(m))
        }
        let preset = s.routingPreset.flatMap(RoutingPreset.init(rawValue:)) ?? .default
        var overrides: [ModelRole: String] = [:]
        for (k, v) in s.modelRoleAssignments() { if let role = ModelRole.of(k) { overrides[role] = v } }
        let plan = AdaptivePlan.plan(query: q, statuses: statuses, preset: preset, overrides: overrides,
                                     activeModelId: services.answerModel()?.id ?? s.activeModelId("llm"),
                                     deviceRamBytes: services.totalRamBytes, maxTokens: maxTokens)
        let tweaks = s.engineTweaks
        let r = try await PlanExecutor(host: services.host, retriever: services.retriever, stages: stages, timeoutFor: { tweaks.stageTimeoutMs(nPredict: $0) })
            .execute(plan: plan.plan, input: PipelineInput(query: q, systemPrompt: systemPrompt, styleReminder: styleReminder, history: history),
                     onToken: { sink.yield(.piece($0)) },
                     onStepStart: { step in
                         sink.yield(.activity(step.type == .retrieve ? .retrieving : .thinking))
                         if step.type == .generate, let id = step.modelId {
                             let other = id == services.answerModel()?.id ? nil : services.catalog.byId(id)?.friendlyName
                             sink.yield(.routed(other))
                         }
                     },
                     shouldStop: { stop.value })
        if r.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !stop.value {
            throw ChatError.adaptive(r.warnings.joined(separator: ", "))
        }
        return (r.citations, r.timedOut)
    }

    /// Stops a title or summary still being written instead of making the question wait for it.
    private func stopBackground() async {
        guard let running = background else { return }
        running.cancel()
        services.host.cancel()
        await running.value
        background = nil
    }

    /// After an answer: a new chat gets a model-written title (autoGenerateTitles); a long one gets its older turns
    /// summarized (autoSummarize, past historyTurnThreshold), in the background.
    private func afterAnswer(sessionId: String, isNewSession: Bool, stopped: Bool, all: [ChatItem], systemPrompt: String?, hadSources: Bool, filesOnly: Bool) {
        if stopped { return }
        let s = services.settings
        guard let session = services.host.current else { return }
        let services = services
        let gen = SessionEngine(session)
        let thinking = s.engineTweaks.thinkingEnabled
        if isNewSession && s.autoGenerateTitles {
            guard let first = all.first(where: { $0.isUser })?.text else { return }
            background = Task {
                if let title = try? await Summarize.title(gen, firstUserMessage: first), !Task.isCancelled {
                    _ = try? await services.background { try $0.chats.setTitle(sessionId: sessionId, title: title) }
                    self.onSessionsChanged?()
                }
                if !Task.isCancelled { await Self.warmPrefix(session, systemPrompt: systemPrompt, withSources: hadSources, filesOnly: filesOnly, thinking: thinking) }
            }
        } else if s.autoSummarize && all.count / 2 > s.historyTurnThreshold {
            let older = Array(all.dropLast(Self.verbatimMessageCount))
            if older.isEmpty { return }
            background = Task {
                let previous = try? await services.background { try $0.chats.listSessions().first { $0.id == sessionId }?.summary }
                // Bounded like the answer's history: a whole detailed chat took tens of seconds to read.
                let turns = HistoryBudget.budget(older.map { ConversationTurn(role: $0.role, text: $0.isUser ? $0.text : AnswerText.stripThinking($0.text)) })
                if let summary = try? await Summarize.summary(gen, turns: turns, previousSummary: previous ?? nil), !Task.isCancelled {
                    _ = try? await services.background { try $0.chats.setSummary(sessionId: sessionId, summary: summary) }
                }
                if !Task.isCancelled { await Self.warmPrefix(session, systemPrompt: systemPrompt, withSources: hadSources, filesOnly: filesOnly, thinking: thinking) }
            }
        }
    }

    /// A title or summary left its own prompt in the KV cache: prefill the answer's system head back so the next
    /// question reuses it (#72's warm-up).
    nonisolated private static func warmPrefix(_ session: any TextModelSession, systemPrompt: String?, withSources: Bool, filesOnly: Bool, thinking: Bool) async {
        // Personal Files answers from the files-only prompt, with its sources.
        let (head, plain) = RagPure.answerPromptPrefix(systemPrompt: systemPrompt, withContext: withSources || filesOnly, filesOnly: filesOnly)
        let input: GenerationRequest.Input = session.capabilities.hasChatTemplate ? .messages([ChatMessage(role: .system, content: head)]) : .prompt(plain)
        await session.prewarm(input, enableThinking: thinking)
    }

    /// How often an answer being written is saved (android PARTIAL_SAVE_NS).
    private static let partialSaveEvery = Duration.seconds(3)

    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

/// A Boar Labs tool answered: leaves the generation block without a model.
private struct InstantAnswer: Error {}

/// The staged answer ran to its end (it loads the model and writes its own steps): skips the other paths.
private struct StagedAnswerRan: Error {}

enum ChatError: LocalizedError {
    case noModel
    /// The answer ended without a word, without an error and without Stop.
    case emptyAnswer
    case adaptive(String)
    case remoteUnreachable(String)

    var errorDescription: String? {
        switch self {
        case .noModel: String(localized: "No answer model is installed.")
        case .emptyAnswer: String(localized: "The model stopped without writing an answer.")
        case .adaptive(let w): String(localized: "Adaptive routing produced no answer: \(w)")
        case .remoteUnreachable(let why): why
        }
    }
}

/// The Stop button's flag, read by the engine's `shouldStop` closures on their own tasks.
final class StopFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    var value: Bool { flag.load(ordering: .relaxed) }
    func set(_ v: Bool) { flag.store(v, ordering: .relaxed) }
}

#if DEBUG
extension ChatController {
    /// UI audit (`-uiScreen chat-streaming`): an answer in progress under the open chat, without a model.
    func debugShowAnswering(question: String, partial: String, activity: ChatActivity, deepResearch: Bool) {
        let answerId = "debug-answer"
        let start = Date.now.addingTimeInterval(-6)
        var item = ChatItem(id: answerId, role: "assistant", text: partial)
        switch activity {
        case .researching:
            item.steps = [AnswerStep(kind: .splitting, startedAt: start),
                          AnswerStep(kind: .subQuestion, startedAt: start.addingTimeInterval(2.1), index: 2, count: 4)]
        case .retrieving:
            item.steps = [AnswerStep(kind: .searching, startedAt: start)]
        default:
            item.steps = [AnswerStep(kind: .searching, startedAt: start), AnswerStep(kind: .thinking, startedAt: start.addingTimeInterval(0.4)),
                          AnswerStep(kind: .writing, startedAt: start.addingTimeInterval(3.6))]
            item.sourceCount = 3
        }
        messages += [ChatItem(id: "debug-question", role: "user", text: question), item]
        answeringId = answerId
        self.activity = activity
        self.deepResearch = deepResearch
        liveTokPerSec = partial.isEmpty ? nil : 9.4
    }

    /// UI audit (`-uiScreen chat-queue`): questions waiting behind the answer in progress.
    func debugQueue(_ questions: [String]) {
        for q in questions { _ = flow.admit(q, running: true, fromQueue: false, behindNote: false, noteUp: false) }
    }

    /// UI audit (`-uiScreen chat-keep-going`): a new chat whose latest answer is Detailed, after a "Go deeper" step, so the
    /// bubbles show under it and the step's verb shows on the user's side.
    func debugShowKeepGoing() {
        func receipt(_ style: String) -> Receipt {
            Receipt(totalMs: 4200, ttftMs: 900, tokPerSec: 14, tokens: 60, model: "Qwen3 1.7B", retrievalMs: 80, prefillMs: nil, contextTokens: nil,
                    loadMs: nil, styleNote: nil, tool: nil, path: nil, style: style)
        }
        var first = ChatItem(id: "debug-kg-a1", role: "assistant", text: "The sky is blue because air scatters short wavelengths of sunlight more than long ones.")
        first.receipt = receipt("succinct")
        var second = ChatItem(id: "debug-kg-a2", role: "assistant", text: "Sunlight holds every color. Air molecules scatter the short, blue wavelengths about ten times more than red, so blue reaches your eye from every direction (Rayleigh scattering). At sunset the light crosses more air, the blue is scattered away and the reds remain.")
        second.receipt = receipt("detailed")
        messages = [ChatItem(id: "debug-kg-q1", role: "user", text: "Why is the sky blue?"), first,
                    ChatItem(id: "debug-kg-q2", role: "user", text: "Why is the sky blue?", step: .deeper), second]
    }

    /// UI audit (`-uiScreen chat-error / chat-no-model`): a question whose answer failed.
    func debugShowFailure(question: String, noModel: Bool) {
        var item = ChatItem(id: "debug-failed", role: "assistant", text: "")
        item.failureNoModel = noModel
        item.failure = noModel
            ? String(localized: "No answer model is installed. Download one in Models.")
            : "The model stopped unexpectedly while writing the answer."
        messages += [ChatItem(id: "debug-failed-question", role: "user", text: question), item]
    }

    /// UI audit (`-uiScreen chat-load-crash`): the notice after a model closed the app while loading.
    func debugShowLoadCrash() {
        loadCrash = LoadGuard.Crash(crashedModelId: "qwen3-4b-instruct-2507-q4km", crashedLabel: "Qwen3-4B-Instruct-2507",
                                    fallbackModelId: "qwen2.5-1.5b-instruct-q4km", fallbackLabel: "Qwen2.5-1.5B-Instruct", at: 0)
    }
}
#endif
