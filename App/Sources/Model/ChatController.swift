import BoarAnswer
import BoarAppleAI
import BoarCore
import BoarModels
import BoarRAG
import BoarRouting
import Foundation
import Observation
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
    /// The answering model's catalog label (the receipt keeps it).
    private(set) var modelLabel: String?
    /// The answering model's plain name ("Fast", "Accurate"), for the chat's subtitle.
    private(set) var modelName: String?
    /// Where it runs: "on this \(Platform.deviceNoun)", "on this Mac", "on mac-mini.local:8080".
    private(set) var modelPlace = String(localized: "on this \(Platform.deviceNoun)")
    private(set) var noModel = false
    private(set) var technicalDetails = false
    private(set) var loadingModel = false
    private(set) var personalityId: String
    private(set) var stopping = false
    private(set) var suggestions: [String] = []
    private(set) var deepResearch = false
    /// A failure before the answer row exists (the chat couldn't be created).
    var error: String?
    /// CR-2, shown once: the model that closed the app and the one answering instead.
    var loadCrash: LoadGuard.Crash?
    /// A short message over the chat (Toast.tsx): the new tone, a reused question.
    var toast: String?

    @ObservationIgnored let services: BoarServices
    /// Called after a session is created, renamed by the model, or pruned (the sidebar reloads).
    @ObservationIgnored var onSessionsChanged: (@MainActor () -> Void)?
    @ObservationIgnored private var job: Task<Void, Never>?
    /// A chat title or summary still being written; a new question stops it (one model, one generation).
    @ObservationIgnored private var background: Task<Void, Never>?
    @ObservationIgnored private let stopFlag = StopFlag()

    init(services: BoarServices) {
        self.services = services
        personalityId = services.settings.personalityId ?? services.personalities.defaultId
        deepResearch = services.settings.deepResearchMode
        technicalDetails = services.settings.showLiveStats
        refreshModel()
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
        toast = String(localized: "Answers will be \(services.personalities.get(id).label)")
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
        refreshModel()
        // The open chat was erased (Clear all chat history, a forgotten PIN): start a new one.
        if let open = sessionId {
            let exists = (try? await services.background { try $0.chats.listSessions().contains { $0.id == open } }) ?? true
            if !exists { newChat() }
        }
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
        suggestions = services.suggestions.forModel(m?.id, language: "en", installed: installed)
    }

    /// Loads the model when the chat opens, so the first answer doesn't wait for it.
    func preload() {
        guard services.activeModel() != nil || services.backend != .llama, !loadingModel else { return }
        loadingModel = true
        let services = services
        Task {
            _ = await services.activeSession()
            let crash = services.loadGuard.consume()
            self.loadingModel = false
            self.loadCrash = crash
            if crash != nil || services.backend == .remote { self.refreshModel() }
        }
    }

    // MARK: sessions

    func newChat() {
        guard job == nil else { return }
        sessionId = nil
        messages = []
        error = nil
    }

    func openSession(_ id: String) {
        guard job == nil, id != sessionId else { return }
        Task {
            let records = (try? await services.background { try $0.chats.messages(sessionId: id) }) ?? []
            self.messages = records.map { r in
                ChatItem(id: r.id, role: r.role, text: r.text, sources: MessageMeta.sources(r.meta), feedback: r.feedback, receipt: MessageMeta.receipt(r.meta))
            }
            self.sessionId = id
            self.error = nil
        }
    }

    /// The chat and its messages; the open one becomes a new chat. Not the chat still being answered.
    func deleteSession(_ id: String) async {
        if job != nil && sessionId == id { return }
        _ = try? await services.background { try $0.chats.deleteSession(sessionId: id) }
        if sessionId == id { newChat() }
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
        Task { _ = try? await services.background { try $0.chats.setFeedback(messageId: messageId, rating: next) } }
    }

    // MARK: answering

    func stop() {
        stopFlag.set(true)
        if answeringId != nil { stopping = true }
        services.host.cancel()
    }

    func send(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, job == nil else { return }
        stopFlag.set(false)
        job = Task {
            await self.answer(q)
            self.job = nil
        }
    }

    /// The question an answer replied to (the user message just before it).
    func question(for answerId: String) -> String? {
        guard let i = messages.firstIndex(where: { $0.id == answerId }), i > 0, messages[i - 1].isUser else { return nil }
        return messages[i - 1].text
    }

    /// Try Again on a failed answer: the failed row goes away and the same question is answered again, under the same
    /// saved question (a failed answer with no text was never saved).
    func retry(_ answerId: String) {
        guard job == nil, let i = messages.firstIndex(where: { $0.id == answerId }), i > 0, messages[i - 1].isUser else { return }
        let question = messages[i - 1]
        messages.remove(at: i)
        stopFlag.set(false)
        job = Task {
            await self.answer(question.text, savedQuestionId: question.id)
            self.job = nil
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
    }

    private func answer(_ q: String, savedQuestionId: String? = nil) async {
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
        if savedQuestionId == nil {
            _ = try? await services.background { try $0.chats.addMessage(sessionId: sid, role: "user", text: q, id: userId) }
        }
        sessionId = sid
        error = nil
        answeringId = answerId
        activity = nil
        liveTokPerSec = nil
        if savedQuestionId == nil { messages.append(ChatItem(id: userId, role: "user", text: q)) }
        messages.append(ChatItem(id: answerId, role: "assistant", text: ""))
        if isNewSession { onSessionsChanged?() }

        let chosenStyle = settings.personalityId ?? services.personalities.defaultId
        // Personal Files: only the user's own files, whole; no Deep Research, router or recap of the library.
        let personal = PersonalFiles.isOn(chosenStyle)
        // A small answer model (the 1.5B) gets Detailed without D4's "Always do what the user asks" (r4to, Oct 18).
        let smallModel = (services.answerModel()?.sizeBytes ?? .max) < Personalities.smallModelBytes
        let (systemPrompt, styleReminder) = services.personalities.promptFor(chosenStyle, customPrompt: settings.customSystemPrompt, smallModel: smallModel)
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
        let way = AnswerPath.of(
            deepResearch: deepResearch && !personal, aboutConversation: Self.aboutConversation(q, history, conversation),
            adaptive: !personal && settings.adaptiveRoutingEnabled, smallTalk: smallTalk
        )

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

        let mark = BoarPerf.begin("answer", way.rawValue)

        func onPiece(_ piece: String) {
            tokens += 1
            let now = clock.now
            if firstAt == nil {
                firstAt = now
                BoarPerf.event("answer.firstToken")
            }
            text += piece
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

        do {
            if services.host.current == nil { enter(.loadingModel, answerId: answerId) }
            guard let session = await services.activeSession() else {
                if services.backend == .remote {
                    throw ChatError.remoteUnreachable(services.host.lastRemoteError ?? String(localized: "Add the Mac's address in Settings → Advanced → Engine."))
                }
                noModel = true
                throw ChatError.noModel
            }
            loadMs = services.host.lastLoadMs
            let openedContext = session.capabilities.contextTokens ?? services.host.openedContext
            var maxTokens = settings.answerTokens(openedContext: openedContext)
            // A thank-you or greeting: Succinct's length in any style.
            if smallTalk { maxTokens = min(maxTokens, AppSettings.defaultMaxTokens) }
            if way != .pipeline {
                let (events, sink) = AsyncStream<Event>.makeStream()
                let stop = stopFlag
                let previousAnswer = lastAnswer.map { AnswerText.stripThinking($0.text) }
                let work = Task.detached { () throws -> Outcome in
                    defer { sink.finish() }
                    if way == .research || way == .recap {
                        let research = way == .research
                        let r = try await DeepResearch(generator: SessionEngine(session, enableThinking: tweaks.thinkingEnabled), retriever: services.retriever, tweaks: tweaks)
                            .run(q, systemPrompt: systemPrompt, history: history, maxTokens: maxTokens,
                                 onProgress: { p in
                                     sink.yield(.activity(research
                                         ? .researching(p.stage, index: p.subQuestionIndex.map { $0 + 1 }, count: p.subQuestionCount) : .thinking))
                                 },
                                 onToken: { sink.yield(.piece($0)) }, shouldStop: { stop.value },
                                 previousAnswer: previousAnswer, conversation: conversation)
                        return Outcome(sources: r.citations, timedOut: r.timedOut, metrics: r.metrics, fromPreviousAnswer: r.fromPreviousAnswer)
                    }
                    let (chunks, timedOut) = try await Self.adaptive(q, systemPrompt: systemPrompt, styleReminder: styleReminder, history: history,
                                                                      maxTokens: maxTokens, services: services, stop: stop, sink: sink)
                    return Outcome(sources: chunks, timedOut: timedOut)
                }
                for await e in events {
                    switch e {
                    case .piece(let p): onPiece(p)
                    case .activity(let a): if firstAt == nil { enter(a, answerId: answerId) }
                    }
                }
                let outcome = try await work.value
                (sources, timedOut) = (outcome.sources, outcome.timedOut)
                if outcome.metrics != nil { metrics = outcome.metrics }
                if outcome.fromPreviousAnswer { reusedSources = lastAnswer?.sources }
            } else {
                let pipeline = AnswerPipeline(session: session, retriever: services.retriever, params: personal ? PersonalFiles.retrieval() : .default)
                var request = AnswerRequest(query: q, systemPrompt: systemPrompt, styleReminder: styleReminder, maxTokens: maxTokens,
                                            history: history, enableThinking: tweaks.thinkingEnabled)
                if personal {
                    // Nothing found in the files: the fixed line, then where to switch a collection on when none is on, or
                    // how to ask when one is. The prompt lists the switched-on files by name.
                    let ownFiles = (try? await services.background { try $0.retriever.ownFiles() }) ?? []
                    let hint = ownFiles.isEmpty
                        ? String(localized: "Check that the collection is switched on in Documents.")
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
                            messages[i].sources = chunks.enumerated().map { ChatSource(number: $0.offset + 1, chunk: $0.element) }
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
        } catch {
            failure = error
        }

        mark.end("\(tokens) tokens\(failure == nil ? "" : ", failed")")
        // A model that opens with the not-found line and then answers from the files keeps only the answer.
        if personal {
            let kept = PersonalFiles.dropHedge(text)
            if kept != text { text = kept }
        }
        let shown = reusedSources ?? sources.enumerated().map { ChatSource(number: $0.offset + 1, chunk: $0.element) }
        let stopped = stopFlag.value
        var receipt: Receipt?
        if let firstAt, tokens > 0 {
            let end = clock.now
            let wallRate = Double(tokens) / max(Self.seconds(firstAt.duration(to: end)), 1e-3)
            let decodeRate = metrics?.decodeTokPerSec ?? 0
            receipt = Receipt(
                totalMs: Self.seconds(startAt.duration(to: end)) * 1000, ttftMs: Self.seconds(startAt.duration(to: firstAt)) * 1000,
                tokPerSec: decodeRate > 0 ? decodeRate : wallRate, tokens: (metrics?.generatedTokens ?? 0) > 0 ? metrics!.generatedTokens : tokens,
                model: modelLabel, retrievalMs: retrievalMs, prefillMs: metrics?.prefillMs, contextTokens: metrics?.promptTokens, loadMs: loadMs)
        }
        let finalText = text
        let meta = (!shown.isEmpty || receipt != nil) ? MessageMeta.encode(shown, receipt) : nil
        let maxSessions = settings.maxSavedSessions
        // A failed answer with no text stays on screen (with Try Again) but is not saved.
        let keep = failure == nil || !finalText.isEmpty
        _ = try? await services.background { s in
            if keep {
                try s.chats.upsertMessage(sessionId: sid, role: "assistant", text: finalText, id: answerId)
                if let meta { try s.chats.setMessageMeta(messageId: answerId, meta: meta) }
            }
            try s.chats.prune(maxSessions: maxSessions)
        }
        if let i = messages.lastIndex(where: { $0.id == answerId }) {
            messages[i].text = finalText
            messages[i].sources = shown
            if messages[i].steps.contains(where: { $0.kind == .searching }) { messages[i].sourceCount = shown.count }
            messages[i].stopped = stopped
            messages[i].timedOut = timedOut
            messages[i].receipt = receipt
            messages[i].answerSeconds = Self.seconds(startAt.duration(to: clock.now))
            if let failure {
                messages[i].failureNoModel = { if case ChatError.noModel = failure { true } else { false } }()
                messages[i].failure = messages[i].failureNoModel
                    ? String(localized: "No answer model is installed. Download one in Models.")
                    : failure.localizedDescription
            }
        }
        answeringId = nil
        activity = nil
        stopping = false
        let all = prior + [ChatItem(id: userId, role: "user", text: q), ChatItem(id: answerId, role: "assistant", text: finalText)]
        if keep {
            afterAnswer(sessionId: sid, isNewSession: isNewSession, stopped: stopped, all: all, systemPrompt: systemPrompt, hadSources: !sources.isEmpty, filesOnly: personal)
        }
        onSessionsChanged?()
    }

    /// runAdaptiveChat: plan with the installed models and the user's routing settings, then execute.
    nonisolated private static func adaptive(
        _ q: String, systemPrompt: String, styleReminder: String?, history: ConversationHistory, maxTokens: Int,
        services: BoarServices, stop: StopFlag, sink: AsyncStream<Event>.Continuation
    ) async throws -> ([Chunk], Bool) {
        let s = services.settings
        let statuses = services.catalog.models.filter { $0.kind == .llm }.map { m in
            Profiles.AvailableModel(RoutableModel(id: m.id, isLanguageModel: true, sizeBytes: m.sizeBytes, roles: m.capabilities?.roles,
                                                  estimatedMemoryMb: m.capabilities?.estimatedMemoryMb,
                                                  estimatedTokensPerSecond: m.capabilities?.estimatedTokensPerSecond),
                                    present: services.isPresent(m))
        }
        let preset = s.routingPreset.flatMap(RoutingPreset.init(rawValue:)) ?? .default
        var overrides: [ModelRole: String] = [:]
        for (k, v) in s.modelRoleAssignments() { if let role = ModelRole.of(k) { overrides[role] = v } }
        let plan = AdaptivePlan.plan(query: q, statuses: statuses, preset: preset, overrides: overrides, activeModelId: s.activeModelId("llm"),
                                     deviceRamBytes: services.totalRamBytes, maxTokens: maxTokens)
        let tweaks = s.engineTweaks
        let r = try await PlanExecutor(host: services.host, retriever: services.retriever, timeoutFor: { tweaks.stageTimeoutMs(nPredict: $0) })
            .execute(plan: plan.plan, input: PipelineInput(query: q, systemPrompt: systemPrompt, styleReminder: styleReminder, history: history),
                     onToken: { sink.yield(.piece($0)) },
                     onStepStart: { step in sink.yield(.activity(step.type == .retrieve ? .retrieving : .thinking)) },
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

    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

enum ChatError: LocalizedError {
    case noModel
    case adaptive(String)
    case remoteUnreachable(String)

    var errorDescription: String? {
        switch self {
        case .noModel: String(localized: "No answer model is installed.")
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
