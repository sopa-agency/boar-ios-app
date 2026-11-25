import BoarAnswer
import BoarCore
import BoarLlama
import BoarModels
import BoarRAG
import BoarRouting
import Foundation
import os

/// The iOS side of scripts/eval-device.mjs (port of android `DeviceEvalRunner.kt`, byte-compatible requests and rows):
/// takes `Documents/eval/requests/pending.json`, reports in `<requestId>.status.json`, writes `Documents/eval/<runId>.jsonl`
/// and `.run.json`. Runs the legacy pipeline (the fixed-model answer path); adaptive routing and the "answer" pipeline
/// are reported as not supported yet, as on Android. `runConfigs` also backs the Benchmark screen.
///
/// Since v2.0.0 (BOAR-56) a run may follow a bench preset (`BenchPlan`): each of its passes (Succinct, Detailed, Deep
/// Research) per model, its topics' questions with the topics' plugins answering, every row saying its style, level and
/// topic; `<runId>.meta.json` keeps the run for the saved list and `<runId>.scorecard.txt` its scorecard.
///
/// The files live in Documents (not Application Support) so a connected Mac can drop a request and pull the results
/// with `xcrun devicectl device copy to/from --domain-type appDataContainer`.
final class EvalRunner: Sendable {
    struct Progress: Sendable {
        var configIndex: Int
        var configCount: Int
        var queryIndex: Int
        var queryCount: Int
        var config: EvalConfig
        var query: EvalQuery
    }

    struct RunResult: Sendable {
        var runId: String
        var rows: [JSONValue]
        var file: URL
        var stopped: Bool
        var scorecard: Scorecard.Card?
    }

    /// Who started a run and, for a preset, its plan: kept in `<runId>.meta.json` for the saved list, and on every row
    /// (level, topic) so the scorecard can tell topics apart.
    struct RunInfo: Sendable {
        /// "app" (the Benchmark screen) or "request" (a connected computer's device request).
        var source = "app"
        var requestId: String?
        var plan: BenchPlan?
        /// The topic files, for the scorecard; empty: read them here.
        var topics: [String: BenchTopic] = [:]
    }

    /// The plugins that answer and check in a run, taken on the main actor before it starts: a topic's (the plugins
    /// topic), else the ones switched on in the app. `ids`: the topic's labs, written on every row (`labsOn`); nil for
    /// the app's own, as on Android.
    struct RunLabs: Sendable {
        var tools: [any AnswerTool] = []
        var checks: [any AnswerCheck] = []
        var ids: [String]?
        /// The labs whose device reads (Nomad, Vitals) are taken before the tools run (PhoneReads).
        var active: Set<String> = []
    }

    static let adaptiveLabel = "Adaptive routing"
    private static let log = BoarLog.logger("eval")

    let services: BoarServices
    let evalDir: URL
    let store: SavedRunStore
    private let requestsDir: URL
    private let stopRequested = StopFlag()
    private let running = OSAllocatedUnfairLock<LlamaSession?>(initialState: nil)
    private let activeRun = OSAllocatedUnfairLock<String?>(initialState: nil)
    /// The app version on every row, so a saved or exported run says which build answered.
    let appVersion: String
    /// CFBundleVersion, for the exported traces' engine label.
    let build: String

    init(services: BoarServices) {
        self.services = services
        let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        // The runs hold questions and answers: out of backups, like the chats. Recreated the same way below.
        evalDir = AppPaths.backupExcludedDirectory(docs.appending(path: "eval", directoryHint: .isDirectory))
        store = SavedRunStore(dir: evalDir)
        requestsDir = evalDir.appending(path: "requests", directoryHint: .isDirectory)
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// The run going now, so the saved list doesn't call it interrupted.
    var activeRunId: String? { activeRun.withLock { $0 } }

    /// Installed language models from the catalog, in catalog order.
    func installedModels() -> [ModelRef] {
        services.catalog.models.filter { $0.kind == .llm && services.isInstalled($0) }.map { ModelRef(id: $0.id, label: $0.label) }
    }

    func evalSets() throws -> EvalSets { try EvalSets.bundled() }

    /// The topic files (BoarModels' Topics), the newest version of each, by id.
    func topics() -> [String: BenchTopic] { BenchTopic.bundled() }

    /// Saved runs, oldest first (Settings' telemetry).
    func savedRuns() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: evalDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.sorted { Self.modified($0) < Self.modified($1) }
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: device requests

    /// The request a connected computer left, removed as it is taken. Nil when there's none.
    func takePending() -> String? {
        let pending = requestsDir.appending(path: "pending.json")
        guard let data = try? Data(contentsOf: pending) else { return nil }
        try? FileManager.default.removeItem(at: pending)
        return String(decoding: data, as: UTF8.self)
    }

    func writeStatus(_ requestId: String, _ fields: [(String, JSONValue?)]) {
        AppPaths.backupExcludedDirectory(evalDir)
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        let all: [(String, JSONValue?)] = [("requestId", .string(requestId))] + fields + [("updatedAt", .int(Self.nowMs()))]
        try? Data(Self.object(all).jsonString.utf8).write(to: requestsDir.appending(path: "\(requestId).status.json"), options: .atomic)
    }

    // MARK: running

    /// Stops after the current answer, which is cut short and recorded as cancelled; the rows so far stay saved.
    func stop() {
        stopRequested.set(true)
        running.withLock { $0 }?.cancel()
    }

    /// Answers every query with every configuration, one model loaded at a time, saving `<runId>.jsonl` after each row
    /// (evalHarness.runEvaluation). A preset (`info.plan`) runs each of its passes (Succinct, Detailed, Deep Research) per
    /// model; otherwise one pass in the default style. `searchOnly`: only each question's search, its sources with their
    /// scores; no answer (a device request's "searchOnly"). `say`: the run's log lines, as they happen.
    func runConfigs(_ configs: [EvalConfig], _ queries: [EvalQuery], info: RunInfo = RunInfo(), labs: RunLabs = RunLabs(), searchOnly: Bool = false,
                    onStart: @escaping @Sendable (String) -> Void = { _ in },
                    onProgress: @escaping @Sendable (Progress) -> Void,
                    onRow: @escaping @Sendable (JSONValue) -> Void,
                    say: @escaping @Sendable (String) -> Void = { _ in }) async throws -> RunResult {
        stopRequested.set(false)
        let runId = DeviceEval.newRunId()
        activeRun.withLock { $0 = runId }
        defer { activeRun.withLock { $0 = nil } }
        AppPaths.backupExcludedDirectory(evalDir)
        let rowsFile = evalDir.appending(path: "\(runId).jsonl")
        let runFile = evalDir.appending(path: "\(runId).run.json")
        var rows: [JSONValue] = []
        let personalities = try Personalities.bundled()
        // The same Auto engine settings as Android's runner (EngineTweaks()), not the user's Advanced tweaks.
        let params = EngineTweaks().resolve(services.topology, totalRamBytes: services.totalRamBytes).params
        let plan = info.plan
        let passes = plan?.passes ?? [BenchPass(personalities.defaultId)]
        let idsOf: (BenchPass) -> Set<String>? = { p in plan?.passQueries[p.key].map(Set.init) }
        let perConfig = passes.reduce(0) { $0 + (idsOf($1)?.count ?? queries.count) }
        let topics = plan.map { _ in info.topics.isEmpty ? self.topics() : info.topics }
        var meta = RunMeta(runId: runId, createdAt: Self.nowMs(), appVersion: appVersion,
                           models: configs.map { if case .model(let id, _) = $0 { id } else { $0.id } },
                           level: plan?.preset.level.id, topics: plan?.preset.topics ?? [],
                           topicVersions: Dictionary((plan?.preset.topics ?? []).compactMap { t in topics?[t].map { (t, $0.version) } },
                                                     uniquingKeysWith: { _, last in last }),  // a topic named twice: Kotlin's toMap()
                           passes: passes.map(\.key), source: info.source, requestId: info.requestId)
        store.writeMeta(meta)
        onStart(runId)
        say("[EVAL] run \(runId): \(configs.map(\.id).joined(separator: ", ")) × \(perConfig) answers" + (plan.map { " (preset \($0.preset.name))" } ?? ""))

        configLoop: for (ci, config) in configs.enumerated() {
            var session: LlamaSession?
            var loaded = false
            var loadMs = 0.0
            var residency = "cold"
            var small = false
            var qi = 0
            defer { if let s = session { Task { await s.close() } } }
            for pass in passes {
                for q in queries {
                    if let ids = idsOf(pass), !ids.contains(q.id) { continue }
                    if stopRequested.value { break configLoop }
                    let runStyle = pass.style
                    let maxTokens = AppSettings.autoMaxTokens(personalityId: runStyle)
                    onProgress(Progress(configIndex: ci, configCount: configs.count, queryIndex: qi, queryCount: perConfig, config: config, query: q))
                    qi += 1
                    let run = Self.object([("runId", .string(runId)), ("configs", JSONValue(strings: configs.map(\.id))),
                                           ("queries", JSONValue(strings: queries.map(\.id))), ("current", .string("\(config.id) / \(pass.key) / \(q.id)"))])
                    try? Data(run.jsonString.utf8).write(to: runFile, options: .atomic)
                    let row: JSONValue
                    switch config {
                    case .adaptive:
                        row = failureRow(runId, config, q, runStyle, maxTokens, "adaptive routing is not in the native build yet")
                    case .model(let modelId, _):
                        if !loaded {
                            loaded = true
                            let start = ContinuousClock.now
                            if let asset = services.catalog.byId(modelId), services.isInstalled(asset) {
                                small = asset.sizeBytes < Personalities.smallModelBytes
                                session = try? await LlamaSession.load(path: services.fileOf(asset).path(percentEncoded: false), params: params)
                            }
                            loadMs = Self.ms(start.duration(to: .now))
                        } else {
                            residency = "resident"
                            loadMs = 0
                        }
                        if let s = session {
                            if searchOnly {
                                row = await searchRow(runId: runId, config: config, modelId: modelId, q: q, personalityId: runStyle, maxTokens: maxTokens,
                                                      residency: residency, loadMs: loadMs)
                            } else {
                                // Said before the answer, so the screen shows what it's doing during a long one (adam, Nov 12).
                                say("[EVAL] \(q.id): answering on \(modelId) (\(pass.key))…")
                                // The chat's short-answer rules too: small talk, health and seed-phrase questions answer in
                                // Succinct, and small talk at Succinct's length (ShortAnswer, ChatController).
                                let style = ShortAnswer.reason(chosenStyle: runStyle, question: q.query, previousQuestion: nil) != nil ? "succinct" : runStyle
                                let (systemPrompt, styleReminder) = personalities.promptFor(style, customPrompt: nil, smallModel: small)
                                let limit = ShortAnswer.isSmallTalk(q.query) ? min(maxTokens, AppSettings.defaultMaxTokens) : maxTokens
                                running.withLock { $0 = s }
                                var r = pass.deep
                                    ? await deepRow(s, runId: runId, config: config, modelId: modelId, q: q, personalityId: style, systemPrompt: systemPrompt,
                                                    maxTokens: limit, residency: residency, loadMs: loadMs)
                                    : await answerRow(s, runId: runId, config: config, modelId: modelId, q: q, personalityId: style, systemPrompt: systemPrompt,
                                                      styleReminder: styleReminder, maxTokens: limit, residency: residency, loadMs: loadMs, labs: labs)
                                running.withLock { $0 = nil }
                                if stopRequested.value, case .object(var o) = r {
                                    o["outcome"] = .string("cancelled")
                                    r = .object(o)
                                }
                                row = r
                            }
                        } else {
                            row = failureRow(runId, config, q, runStyle, maxTokens, "model failed to load")
                        }
                    }
                    // Every row says the pass's style, whatever the question answered in (personalityId); a preset's rows
                    // also say its level and the question's topic.
                    var extra: [(String, JSONValue?)] = [("style", .string(runStyle))]
                    if let plan {
                        extra.append(("level", .string(plan.preset.level.id)))
                        if let t = plan.topicOf[q.id] {
                            extra.append(("topic", .string(t)))
                            extra.append(("topicVersion", topics?[t].map { JSONValue($0.version) }))
                        }
                    }
                    if let ids = labs.ids { extra.append(("labsOn", JSONValue(strings: ids))) }
                    let checked = Self.withCheck(Self.adding(extra, to: row), q)
                    rows.append(checked)
                    try? Data(rows.map { $0.jsonString + "\n" }.joined().utf8).write(to: rowsFile, options: .atomic)
                    meta.rows = rows.count
                    store.writeMeta(meta)
                    onRow(checked)
                    let line = "[EVAL] \(q.id): \(checked["outcome"]?.stringValue ?? "?") \(checked["tokPerSec"]?.doubleValue.map { String(format: "%.1f tok/s", $0) } ?? "")"
                    say(line)
                    Self.log.info("\(line, privacy: .public) \(checked["check"]?.stringValue ?? "-", privacy: .public)")
                }
            }
            if let s = session {
                session = nil
                await s.close()
            }
        }
        try? FileManager.default.removeItem(at: runFile)
        // The scorecard (t9 0521 item 4), against the last run of the same level and topics; kept as text beside the rows.
        let previous = store.previous(meta, all: store.list(active: runId)).map { store.rows($0.runId) }
        let card = Scorecard.of(rows, topics: topics ?? (info.topics.isEmpty ? self.topics() : info.topics), previous: previous)
        let text = Scorecard.text(card)
        try? Data(text.utf8).write(to: store.scorecardFile(runId), options: .atomic)
        for l in text.split(separator: "\n") where !l.allSatisfy(\.isWhitespace) { say("[EVAL] score \(l)") }
        let stopped = stopRequested.value
        meta.state = stopped ? RunMeta.stateStopped : RunMeta.stateDone
        meta.rows = rows.count
        meta.finishedAt = Self.nowMs()
        store.writeMeta(meta)
        return RunResult(runId: runId, rows: rows, file: rowsFile, stopped: stopped, scorecard: card)
    }

    private func answerRow(_ s: LlamaSession, runId: String, config: EvalConfig, modelId: String, q: EvalQuery, personalityId: String,
                           systemPrompt: String, styleReminder: String?, maxTokens: Int, residency: String, loadMs: Double, labs: RunLabs) async -> JSONValue {
        // The tool slot (Boar Labs), as in the chat: a tool's instant answer is the row, no generation; a context is read
        // by the model. Nomad's and Vitals' answers read the device first (PhoneReads).
        let toolClock = ContinuousClock()
        let toolStart = toolClock.now
        await PhoneReads.prepare(query: q.query, active: labs.active)
        let tool = AnswerTools.run(labs.tools, query: q.query, history: [])
        if case .instant(let code, let text)? = tool {
            return toolRow(runId: runId, config: config, modelId: modelId, q: q, personalityId: personalityId, maxTokens: maxTokens, residency: residency,
                           loadMs: loadMs, tool: code, text: text, ms: Self.ms(toolStart.duration(to: toolClock.now)))
        }
        let pipeline = AnswerPipeline(session: s, retriever: services.retriever)
        let peak = PeakFootprint()
        peak.start()
        let clock = ContinuousClock()
        let start = clock.now
        var genStart: ContinuousClock.Instant?
        var firstToken: ContinuousClock.Instant?
        var tokens = 0
        var done: AnswerResult?
        var failure: String?
        do {
            let request = AnswerRequest(query: q.query, systemPrompt: AnswerTools.systemPrompt(systemPrompt, tool), styleReminder: styleReminder, maxTokens: maxTokens)
            for try await e in pipeline.answer(request) {
                switch e {
                case .stage(let stage): if stage == .thinking { genStart = clock.now }
                case .piece:
                    tokens += 1
                    if firstToken == nil { firstToken = clock.now }
                case .done(let r): done = r
                default: break
                }
            }
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        let end = clock.now
        let peakBytes = peak.stop()
        // The check slot, as in the chat: a finished answer may be repaired (Boar Guard).
        let repair = done.flatMap { d in failure == nil && !d.text.allSatisfy(\.isWhitespace) ? AnswerChecks.run(labs.checks, question: q.query, answer: d.text) : nil }
        let answer = repair?.text ?? done?.text ?? ""
        let ttftMs = genStart.map { Self.ms($0.duration(to: firstToken ?? end)) }
        let genLatency = (genStart != nil && ttftMs != nil) ? Self.ms(genStart!.duration(to: end)) - ttftMs! : nil
        let outcome = failure != nil ? "failure" : (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "failure" : "success")
        let m = done?.metrics
        let titles = done?.sources.map(\.title) ?? []
        let taskType = done?.taskType ?? Classify.classifyTask(q.query).value
        let retrieve = !(TaskType(rawValue: taskType).map(Classify.isRetrievalIrrelevant) ?? false)
        let toolCodes = [tool?.tool, repair?.tool].compactMap { $0 }
        return Self.object([
            ("modelId", .string(modelId)), ("taskType", .string(taskType)), ("adaptiveRoutingUsed", .bool(false)),
            ("reasonCodes", JSONValue(strings: DeviceEval.fixedPlanReasonCodes(retrieve: retrieve, modelId: modelId))),
            ("retrievalUsed", .bool(!titles.isEmpty)), ("modelSwitches", .int(0)), ("crossMessageModelSwitch", .bool(false)),
            ("modelResidency", .string(residency)), ("modelLoadMs", .double(loadMs)), ("ttftMs", ttftMs.map(JSONValue.double)),
            ("generationLatencyMs", genLatency.map(JSONValue.double)), ("totalLatencyMs", .double(Self.ms(start.duration(to: end)))),
            ("tokensGenerated", .int(Int64(tokens))), ("tokPerSec", DeviceEval.tokensPerSecond(tokens: tokens, generationLatencyMs: genLatency).map(JSONValue.double)),
            ("peakRssBytes", .int(peakBytes)), ("outcome", .string(outcome)),
            ("errorMessage", (failure ?? (outcome == "failure" ? "empty answer" : nil)).map(JSONValue.string)),
            ("runId", .string(runId)), ("evalSetVersion", .string(q.setVersion)), ("retrievalMs", done?.retrievalMs.map(JSONValue.double)),
            ("contextTokensBefore", done?.tokensBefore.map { .int(Int64($0)) }), ("contextTokensAfter", done?.tokensAfter.map { .int(Int64($0)) }),
            ("promptTokens", m.map { .int(Int64($0.promptTokensDecoded)) }), ("promptMs", m.map { .double($0.prefillMs) }),
            ("cachedTokens", m.map { .int(Int64($0.promptTokens - $0.promptTokensDecoded)) }),
            ("predictedTokens", m.map { .int(Int64($0.generatedTokens)) }), ("predictedMs", m.map { .double($0.decodeMs) }),
            ("configId", .string(config.id)), ("configLabel", .string(config.label)), ("personalityId", .string(personalityId)),
            ("maxTokens", .int(Int64(maxTokens))), ("queryId", .string(q.id)), ("category", .string(q.category)), ("query", .string(q.query)),
            ("answer", .string(answer)), ("promptFormat", done.map { .string($0.promptFormat) }),
            ("retrievedTitles", JSONValue(strings: titles)), ("expectedKbTitles", JSONValue(strings: q.expectedKbTitles)),
            ("expectedKbHit", DeviceEval.expectedKbHit(q.expectedKbTitles, retrieved: titles).map(JSONValue.bool)),
            // The user's own files among the sources (a custom collection), for the scorecard's noFileSources rule.
            ("fileSources", JSONValue(strings: (done?.sources ?? []).filter { $0.collectionId != nil }.map(\.title))),
            ("tool", toolCodes.isEmpty ? nil : .string(toolCodes.joined(separator: "+"))),
            ("timedOut", .bool(false)), ("createdAt", .int(Self.nowMs())), ("engine", .string("native")),
            ("appVersion", .string(appVersion)),
        ])
    }

    /// A Deep Research row (the complete level's research topic; adam, Nov 14): DeepResearch as the chat runs it, the
    /// write-up in the question's language. Same fields as `answerRow`, path "deep"; ttftMs is the write-up's first word.
    private func deepRow(_ s: LlamaSession, runId: String, config: EvalConfig, modelId: String, q: EvalQuery, personalityId: String,
                         systemPrompt: String, maxTokens: Int, residency: String, loadMs: Double) async -> JSONValue {
        let peak = PeakFootprint()
        peak.start()
        let clock = ContinuousClock()
        let start = clock.now
        let first = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)
        let count = OSAllocatedUnfairLock<Int>(initialState: 0)
        let stop = stopRequested
        var result: ResearchResult?
        var failure: String?
        do {
            result = try await DeepResearch(generator: SessionEngine(s), retriever: services.retriever)
                .run(q.query, systemPrompt: systemPrompt, history: nil, maxTokens: maxTokens,
                     onToken: { _ in
                         count.withLock { $0 += 1 }
                         first.withLock { if $0 == nil { $0 = clock.now } }
                     },
                     shouldStop: { stop.value },
                     answerLanguage: AnswerLanguage.line(AnswerLanguage.of(q.query), withSources: true))
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        let end = clock.now
        let peakBytes = peak.stop()
        let answer = result?.answer ?? ""
        let firstToken = first.withLock { $0 }
        let tokens = count.withLock { $0 }
        let outcome = failure == nil && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "success" : "failure"
        let ttftMs = firstToken.map { Self.ms(start.duration(to: $0)) }
        let genLatency = firstToken.map { Self.ms($0.duration(to: end)) }
        let titles = result?.citations.map(\.title) ?? []
        let taskType = Classify.classifyTask(q.query)
        let m = result?.metrics
        return Self.object([
            ("modelId", .string(modelId)), ("taskType", .string(taskType.value)), ("adaptiveRoutingUsed", .bool(false)),
            ("reasonCodes", JSONValue(strings: DeviceEval.fixedPlanReasonCodes(retrieve: !Classify.isRetrievalIrrelevant(taskType), modelId: modelId))),
            ("retrievalUsed", .bool(!titles.isEmpty)), ("modelSwitches", .int(0)), ("crossMessageModelSwitch", .bool(false)),
            ("modelResidency", .string(residency)), ("modelLoadMs", .double(loadMs)), ("ttftMs", ttftMs.map(JSONValue.double)),
            ("generationLatencyMs", genLatency.map(JSONValue.double)), ("totalLatencyMs", .double(Self.ms(start.duration(to: end)))),
            ("tokensGenerated", .int(Int64(tokens))), ("tokPerSec", DeviceEval.tokensPerSecond(tokens: tokens, generationLatencyMs: genLatency).map(JSONValue.double)),
            ("peakRssBytes", .int(peakBytes)), ("outcome", .string(outcome)),
            ("errorMessage", (failure ?? (outcome == "failure" ? "empty answer" : nil)).map(JSONValue.string)),
            ("runId", .string(runId)), ("evalSetVersion", .string(q.setVersion)),
            ("promptTokens", m.map { .int(Int64($0.promptTokensDecoded)) }), ("promptMs", m.map { .double($0.prefillMs) }),
            ("predictedTokens", m.map { .int(Int64($0.generatedTokens)) }), ("predictedMs", m.map { .double($0.decodeMs) }),
            ("configId", .string(config.id)), ("configLabel", .string(config.label)), ("personalityId", .string(personalityId)),
            ("maxTokens", .int(Int64(maxTokens))), ("queryId", .string(q.id)), ("category", .string(q.category)), ("query", .string(q.query)),
            ("answer", .string(answer)), ("promptFormat", .string(s.capabilities.hasChatTemplate ? "chat-template" : "plain")),
            ("retrievedTitles", JSONValue(strings: titles)), ("expectedKbTitles", JSONValue(strings: q.expectedKbTitles)),
            ("expectedKbHit", DeviceEval.expectedKbHit(q.expectedKbTitles, retrieved: titles).map(JSONValue.bool)),
            ("fileSources", JSONValue(strings: (result?.citations ?? []).filter { $0.collectionId != nil }.map(\.title))),
            ("timedOut", .bool(result?.timedOut == true)), ("createdAt", .int(Self.nowMs())), ("engine", .string("native")),
            ("appVersion", .string(appVersion)), ("path", .string(BenchPass.pathDeep)), ("subQuestions", result.map { JSONValue(strings: $0.subQuestions) }),
        ])
    }

    /// A row a tool answered: its text, reason code answer:<tool> (as answer.ts's receipts), nothing generated or retrieved.
    private func toolRow(runId: String, config: EvalConfig, modelId: String, q: EvalQuery, personalityId: String, maxTokens: Int, residency: String,
                         loadMs: Double, tool: String, text: String, ms: Double) -> JSONValue {
        Self.object([
            ("modelId", .string(modelId)), ("taskType", .string(Classify.classifyTask(q.query).value)), ("adaptiveRoutingUsed", .bool(false)),
            ("reasonCodes", JSONValue(strings: ["answer:\(tool)"])), ("retrievalUsed", .bool(false)), ("modelSwitches", .int(0)),
            ("crossMessageModelSwitch", .bool(false)), ("modelResidency", .string(residency)), ("modelLoadMs", .double(loadMs)),
            ("ttftMs", .double(ms)), ("totalLatencyMs", .double(ms)), ("tokensGenerated", .int(0)), ("outcome", "success"),
            ("runId", .string(runId)), ("evalSetVersion", .string(q.setVersion)), ("configId", .string(config.id)), ("configLabel", .string(config.label)),
            ("personalityId", .string(personalityId)), ("maxTokens", .int(Int64(maxTokens))), ("queryId", .string(q.id)), ("category", .string(q.category)),
            ("query", .string(q.query)), ("answer", .string(text)), ("retrievedTitles", .array([])),
            ("expectedKbTitles", JSONValue(strings: q.expectedKbTitles)),
            ("expectedKbHit", DeviceEval.expectedKbHit(q.expectedKbTitles, retrieved: []).map(JSONValue.bool)),
            ("timedOut", .bool(false)), ("createdAt", .int(Self.nowMs())), ("engine", .string("native")), ("appVersion", .string(appVersion)),
            ("tool", .string(tool)),
        ])
    }

    /// A search-only row (t9 0321): the sources the answer would get, in order, each with its similarity, fused score,
    /// match type and kind ("pack", "file" for the user's own files, "kb" for the built-in corpus). No answer is written.
    private func searchRow(runId: String, config: EvalConfig, modelId: String, q: EvalQuery, personalityId: String, maxTokens: Int,
                           residency: String, loadMs: Double) async -> JSONValue {
        let clock = ContinuousClock()
        let start = clock.now
        var error: String?
        var found: [Chunk] = []
        do {
            found = try await services.retriever.retrieve(q.query, topK: RagPure.answerContextChunks)
        } catch let e {
            error = (e as? LocalizedError)?.errorDescription ?? String(describing: e)
        }
        let ms = Self.ms(start.duration(to: clock.now))
        let sources: [JSONValue] = found.map { c in
            .object([
                "title": .string(c.title), "similarity": c.similarity.map(JSONValue.double) ?? .null, "score": .double(c.score),
                "match": .string(c.matchType.rawValue),
                "kind": .string(c.docId.hasPrefix("pack:") ? "pack" : c.collectionId != nil ? "file" : "kb"),
            ])
        }
        return Self.object([
            ("modelId", .string(modelId)), ("taskType", .string(Classify.classifyTask(q.query).value)), ("adaptiveRoutingUsed", .bool(false)),
            ("retrievalUsed", .bool(!found.isEmpty)), ("modelResidency", .string(residency)), ("modelLoadMs", .double(loadMs)),
            ("totalLatencyMs", .double(ms)), ("retrievalMs", .double(ms)), ("tokensGenerated", .int(0)),
            ("outcome", .string(error == nil ? "success" : "failure")), ("errorMessage", error.map(JSONValue.string)),
            ("runId", .string(runId)), ("evalSetVersion", .string(q.setVersion)), ("configId", .string(config.id)), ("configLabel", .string(config.label)),
            ("personalityId", .string(personalityId)), ("maxTokens", .int(Int64(maxTokens))), ("queryId", .string(q.id)), ("category", .string(q.category)),
            ("query", .string(q.query)), ("answer", ""), ("retrievedTitles", JSONValue(strings: found.map(\.title))),
            ("retrievedSources", .array(sources)), ("expectedKbTitles", JSONValue(strings: q.expectedKbTitles)),
            ("expectedKbHit", DeviceEval.expectedKbHit(q.expectedKbTitles, retrieved: found.map(\.title)).map(JSONValue.bool)),
            ("timedOut", .bool(false)), ("createdAt", .int(Self.nowMs())), ("engine", .string("native")), ("appVersion", .string(appVersion)),
            ("path", "search-only"),
        ])
    }

    private func failureRow(_ runId: String, _ config: EvalConfig, _ q: EvalQuery, _ personalityId: String, _ maxTokens: Int, _ error: String) -> JSONValue {
        let modelId: JSONValue? = if case .model(let id, _) = config { .string(id) } else { nil }
        let adaptive: Bool = if case .adaptive = config { true } else { false }
        return Self.object([
            ("modelId", modelId), ("taskType", .string(Classify.classifyTask(q.query).value)), ("adaptiveRoutingUsed", .bool(adaptive)),
            ("outcome", .string("failure")), ("errorMessage", .string(error)), ("tokensGenerated", .int(0)), ("runId", .string(runId)),
            ("evalSetVersion", .string(q.setVersion)), ("configId", .string(config.id)), ("configLabel", .string(config.label)),
            ("personalityId", .string(personalityId)), ("maxTokens", .int(Int64(maxTokens))), ("queryId", .string(q.id)),
            ("category", .string(q.category)), ("query", .string(q.query)), ("answer", .string("")), ("retrievedTitles", .array([])),
            ("expectedKbTitles", JSONValue(strings: q.expectedKbTitles)),
            ("expectedKbHit", DeviceEval.expectedKbHit(q.expectedKbTitles, retrieved: []).map(JSONValue.bool)),
            ("timedOut", .bool(false)), ("createdAt", .int(Self.nowMs())), ("engine", .string("native")),
            ("appVersion", .string(appVersion)),
        ])
    }

    // MARK: helpers

    /// The offline grade of a finished row: precheck, source found and the item's bench fields (docs/BENCHMARK-SCREEN.md).
    static func withCheck(_ row: JSONValue, _ q: EvalQuery) -> JSONValue {
        guard case .object(var o) = row else { return row }
        let titles = o["retrievedTitles"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let outcome = BenchCheck.evaluate(q, answer: o["answer"]?.stringValue ?? "", cancelled: o["outcome"]?.stringValue == "cancelled",
                                          retrievedTitles: titles)
        for (k, v) in BenchCheck.rowFields(q, outcome) { if let v { o[k] = v } }
        return .object(o)
    }

    /// `row` with `pairs` set (nil values left out).
    static func adding(_ pairs: [(String, JSONValue?)], to row: JSONValue) -> JSONValue {
        guard case .object(var o) = row else { return row }
        for (k, v) in pairs { if let v { o[k] = v } }
        return .object(o)
    }

    /// A JSON object from pairs; nil values are left out, as JSON.stringify drops undefined.
    static func object(_ pairs: [(String, JSONValue?)]) -> JSONValue {
        var o: [String: JSONValue] = [:]
        for (k, v) in pairs { if let v { o[k] = v } }
        return .object(o)
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

/// The app's peak physical footprint while a question runs, sampled every 250 ms (android PeakRss over VmRSS).
private final class PeakFootprint: Sendable {
    private let peak = OSAllocatedUnfairLock<Int64>(initialState: 0)
    private let sampler = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    func start() {
        peak.withLock { $0 = AppMemory.footprintBytes() }
        let peak = peak
        sampler.withLock {
            $0 = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    let now = AppMemory.footprintBytes()
                    peak.withLock { $0 = max($0, now) }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
    }

    func stop() -> Int64 {
        sampler.withLock { $0?.cancel(); $0 = nil }
        let now = AppMemory.footprintBytes()
        return peak.withLock { max($0, now) }
    }
}
