import BoarAnswer
import BoarCore
import BoarRAG
import BoarRouting
import Foundation
import Observation

/// The Evaluation screen's state (port of android `EvaluationViewModel`, extended with the public bench v0.1 sets,
/// docs/BENCHMARK-SCREEN.md): a question set against the chosen models, graded offline as it runs, saved after each answer
/// and shared as judge-ready traces, JSONL or CSV. Also answers device requests a connected computer leaves in
/// `Documents/eval/requests/pending.json` (DeviceEvalRunner's polling), and shows their progress here.
///
/// Since v2.0.0 (BOAR-56): presets by level and topic (adam, Nov 14: "fast, only succinct mode. medium, complete. and by
/// topics") with their expected time, the scorecard after a run, and every run kept on the device, listed, opened and
/// deleted ("i run, closed, and now, cant review?"). The run's log, newest line first, while it runs.
@MainActor
@Observable
final class EvaluationController {
    private(set) var configs: [EvalConfig]?
    var selected: Set<String> = []
    /// Quick check, Research bench v0.1 and the App smoke set (By hand).
    private(set) var sets: [EvalQuestionSet] = []
    var setKind: EvalQuestionSet.Kind = .quick
    /// The set the shown results came from.
    private(set) var resultSetKind: EvalQuestionSet.Kind?
    /// What the last run started here set out to answer (models × questions); nil for results it didn't run.
    private var runAnswers: Int?
    private(set) var running = false
    private(set) var stopping = false
    private(set) var progress: EvalRunner.Progress?
    private(set) var rows: [JSONValue] = []
    private(set) var runId: String?
    private(set) var savedPath: String?
    private(set) var stopped = false
    var error: String?
    /// The device request being answered (started from a connected computer).
    private(set) var requestId: String?

    /// The preset's level; nil: by hand (the ticked models and the chosen set, in the default style), as before.
    private(set) var level: BenchLevel?
    /// The preset's topic ("core": the fixed 17).
    private(set) var topic = BenchPresets.core
    /// The topic files, the fixed 17 first, then in t9's order.
    private(set) var topics: [BenchTopic] = []
    /// What the chosen preset runs, and how long it should take.
    private(set) var plan: BenchPlan?
    private(set) var planError: String?
    private(set) var estimate: BenchPresets.Estimate?
    /// The scorecard of the run just made or opened.
    private(set) var scorecard: Scorecard.Card?
    /// Every run kept on the device, newest first.
    private(set) var saved: [RunMeta] = []
    /// The saved run shown, when one was opened from the list.
    private(set) var opened: RunMeta?
    /// The run's log lines, oldest first (BenchLog shows them newest first); and when the last one came.
    private(set) var log: [String] = []
    private(set) var lastLineAt: Date?

    @ObservationIgnored let runner: EvalRunner
    @ObservationIgnored private let services: BoarServices
    /// The chat is answering: an evaluation would fight it for the model and memory.
    @ObservationIgnored var chatBusy: @MainActor () -> Bool = { false }
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// Plain names per model id ("Fast" + "Qwen2.5-1.5B-Instruct").
    @ObservationIgnored private var names: [String: EvalModelName] = [:]
    @ObservationIgnored private var evalSets: EvalSets?
    @ObservationIgnored private var topicsById: [String: BenchTopic] = [:]
    @ObservationIgnored private var installed: [ModelRef] = []

    /// The topics in t9's order (0521 item 3), after the fixed 17.
    static let topicOrder = ["plugins", "problems", "howto", "research", "quick", "cards", "portuguese", "vitalik"]
    /// Log lines kept (BenchLog shows the last `BenchLog.max`).
    private static let logKept = 400

    init(services: BoarServices) {
        self.services = services
        runner = EvalRunner(services: services)
    }

    var appVersion: String { runner.appVersion }

    var questionSet: EvalQuestionSet? { sets.first { $0.kind == setKind } ?? sets.first }
    /// The questions a run asks: the preset's, or the chosen set's by hand.
    var queries: [EvalQuery] { level != nil ? plan?.queries ?? [] : questionSet?.queries ?? [] }
    var byHand: Bool { level == nil }

    /// Per-model and per-category numbers of the shown results.
    var summary: EvalSummary { EvalSummary(rows: rows) }

    /// Each model's score v1 from the shown results, best first (android ScoreSection).
    var scores: [EvalScore.ModelScore] { EvalScore.scoreRun(json: rows) }

    /// The answers the run asks for: every model times every question (at least the answers shown).
    var expectedAnswers: Int {
        if let p = progress { return p.configCount * p.queryCount }
        // A run stopped early still counts what it set out to answer (5/10, not 5/5).
        if let runAnswers { return max(rows.count, runAnswers) }
        if opened != nil { return rows.count }
        let questions = sets.first { $0.kind == resultSetKind }?.queries.count ?? 0
        return max(rows.count, questions * Set(rows.compactMap { $0["configId"]?.stringValue }).count)
    }

    /// The answers Run would ask for now: the preset's plan, or the ticked models times the set by hand.
    var plannedAnswers: Int { byHand ? queries.count * chosen.count : plan?.answers ?? 0 }

    func load() {
        guard configs == nil else { return }
        if sets.isEmpty { sets = EvalQuestionSet.bundled() }
        let models = runner.installedModels()
        installed = models
        for m in models {
            names[m.id] = EvalModelName(asset: services.catalog.byId(m.id), label: m.label)
        }
        configs = models.map { EvalConfig.model(modelId: $0.id, label: $0.label) }
        selected = Set(configs?.map(\.id) ?? [])
        if evalSets == nil { evalSets = try? runner.evalSets() }
        if topicsById.isEmpty {
            topicsById = runner.topics()
            topics = topicsById.values.sorted { a, b in
                (a.id == BenchPresets.core ? 0 : 1, Self.topicOrder.firstIndex(of: a.id) ?? 99, a.id)
                    < (b.id == BenchPresets.core ? 0 : 1, Self.topicOrder.firstIndex(of: b.id) ?? 99, b.id)
            }
        }
        replan()
        refreshSaved()
    }

    /// The plain name of a config ("Fast" · "Qwen2.5-1.5B-Instruct"); adaptive routing and unknown models keep their label.
    func name(configId: String, label: String) -> EvalModelName {
        if configId.hasPrefix("model:"), let n = names[String(configId.dropFirst("model:".count))] { return n }
        return EvalModelName(asset: nil, label: label)
    }

    func name(_ config: EvalConfig) -> EvalModelName { name(configId: config.id, label: config.label) }

    /// The installed models changed (a download or a removal).
    func reloadConfigs() {
        configs = nil
        load()
    }

    func toggle(_ id: String) {
        guard !running else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// The models a run uses: the ticked ones by hand, the plan's with a preset.
    var chosen: [EvalConfig] {
        if level != nil { return (plan?.models ?? []).map { EvalConfig.model(modelId: $0.id, label: $0.label) } }
        return (configs ?? []).filter { selected.contains($0.id) }
    }

    // MARK: presets

    func setLevel(_ level: BenchLevel?) {
        guard !running else { return }
        self.level = level
        replan()
    }

    func setTopic(_ topic: String) {
        guard !running else { return }
        self.topic = topic
        replan()
    }

    /// The chosen preset's plan and expected time: the last run of the same level on this device, else the F3's medians.
    private func replan() {
        guard let level, let sets = evalSets else {
            plan = nil
            planError = nil
            estimate = nil
            return
        }
        let planned = BenchPresets.plan(BenchPreset(level, [topic]), installed: installed, topics: topicsById, sets: sets)
        plan = planned.plan
        planError = planned.error
        let last = runner.store.lastOfLevel(level.id).map { runner.store.rows($0.runId) }
        estimate = planned.plan.map { BenchPresets.estimate($0, previousRows: last) }
    }

    // MARK: saved runs

    /// Runs started from a connected computer since the page was last open show up too.
    func refreshSaved() {
        let store = runner.store
        let active = runner.activeRunId
        Task {
            let list = await Task.detached(priority: .utility) { store.list(active: active) }.value
            saved = list
        }
    }

    /// Shows a saved run as right after it ran: its rows and its scorecard against the run before it.
    func open(_ runId: String) {
        guard !running else { return }
        let store = runner.store
        let active = runner.activeRunId
        let topics = topicsById
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> (RunMeta, [JSONValue], Scorecard.Card, [RunMeta])? in
                let all = store.list(active: active)
                guard let meta = all.first(where: { $0.runId == runId }) else { return nil }
                let rows = store.rows(runId)
                let previous = store.previous(meta, all: all).map { store.rows($0.runId) }
                return (meta, rows, Scorecard.of(rows, topics: topics, previous: previous), all)
            }.value
            guard let (meta, rows, card, all) = found, !running else { return }
            opened = meta
            self.rows = rows
            self.runId = runId
            savedPath = "Documents/eval/\(runId).jsonl"
            stopped = meta.state == RunMeta.stateStopped
            scorecard = card
            runAnswers = nil
            resultSetKind = nil
            error = nil
            saved = all
        }
    }

    func closeOpened() {
        opened = nil
        rows = []
        runId = nil
        savedPath = nil
        scorecard = nil
        stopped = false
    }

    /// Deletes a saved run (after the screen's confirmation); never the one going now.
    func delete(_ runId: String) {
        guard runner.activeRunId != runId else { return }
        runner.store.delete(runId)
        if self.runId == runId { closeOpened() }
        refreshSaved()
    }

    // MARK: running

    func run() {
        let chosen = chosen
        guard !running, !chosen.isEmpty, !chatBusy() else { return }
        if level != nil {
            guard let plan else { return }
            start(chosen, plan.queries, setKind: nil, requestId: nil, plan: plan)
        } else {
            start(chosen, queries, setKind: setKind, requestId: nil, plan: nil)
        }
    }

    func stop() {
        stopping = true
        runner.stop()
    }

    /// The plugins that answer in a run: a topic's (the plugins topic), else the ones switched on in the app (android
    /// `DeviceEvalRunner.setLabs`). A topic's lab this build leaves out is skipped; its questions then fail their rule.
    static func runLabs(_ ids: [String]?) -> EvalRunner.RunLabs {
        let all = Labs.shared
        guard let ids else {
            return EvalRunner.RunLabs(tools: all.activeTools, checks: all.activeChecks, ids: nil, active: Set(all.active.map(\.id)))
        }
        // "staged" in a topic's labs asked for Staged answers on Android, core since Nov 12: not a lab.
        let labs = ids.filter { $0 != "staged" }.compactMap { all.byId($0) }
        let tools = labs.enumerated()
            .sorted { (LabTools.slotRank($0.element.id), $0.offset) < (LabTools.slotRank($1.element.id), $1.offset) }
            .compactMap(\.element.answerTool)
        return EvalRunner.RunLabs(tools: tools, checks: labs.compactMap(\.answerCheck), ids: labs.map(\.id), active: Set(labs.map(\.id)))
    }

    private func say(_ line: String) {
        log.append(line)
        if log.count > Self.logKept { log.removeFirst(log.count - Self.logKept) }
        lastLineAt = Date()
    }

    private func start(_ configs: [EvalConfig], _ queries: [EvalQuery], setKind: EvalQuestionSet.Kind?, requestId: String?, plan: BenchPlan?,
                       searchOnly: Bool = false, onDone: (@MainActor (EvalRunner.RunResult?, Error?) -> Void)? = nil) {
        running = true
        resultSetKind = setKind
        runAnswers = plan?.answers ?? configs.count * queries.count
        stopping = false
        rows = []
        runId = nil
        savedPath = nil
        stopped = false
        error = nil
        opened = nil
        scorecard = nil
        log = []
        lastLineAt = nil
        self.requestId = requestId
        // A long run with the phone on the desk: the screen stays on (keepScreenOn).
        Platform.keepAwake(true)
        let runner = runner
        let services = services
        let labs = Self.runLabs(plan?.labs)
        let info = EvalRunner.RunInfo(source: requestId == nil ? "app" : "request", requestId: requestId, plan: plan, topics: topicsById)
        let topics = topicsById
        Task {
            var result: EvalRunner.RunResult?
            var failure: Error?
            do {
                // The chat's answer and its queue stop first; still answering after the wait: the run doesn't start.
                guard await services.answers.stopAndWait() else { throw EvalError.answerStillWritten }
                // One model in memory at a time: the chat's is reloaded on its next message.
                await services.host.unload()
                result = try await Task.detached(priority: .userInitiated) {
                    try await runner.runConfigs(configs, queries, info: info, labs: labs, searchOnly: searchOnly,
                                                onStart: { _ in Task { @MainActor in self.refreshSaved() } },
                                                onProgress: { p in Task { @MainActor in self.progress = p } },
                                                onRow: { row in Task { @MainActor in self.rows.append(row) } },
                                                say: { line in Task { @MainActor in self.say(line) } })
                }.value
                if let result {
                    runId = result.runId
                    savedPath = "Documents/eval/\(result.file.lastPathComponent)"
                    stopped = result.stopped
                    rows = result.rows
                    scorecard = result.scorecard ?? Scorecard.of(result.rows, topics: topics)
                    // Boar Avatars: a run from the Evaluation screen that finished (android EvaluationViewModel.run); a
                    // bench request is Android's BenchActivity, which doesn't count.
                    if requestId == nil && !result.stopped { services.vault.record { $0.evalRuns += 1 } }
                }
            } catch {
                failure = error
                self.error = error.localizedDescription
            }
            onDone?(result, failure)
            running = false
            stopping = false
            progress = nil
            Platform.keepAwake(false)
            refreshSaved()
            replan()
        }
    }

    // MARK: export

    /// EvalTrace v1 for one model, the file `harness/judge.mjs` and `scorers/score.py` read (one system per file).
    func traceFile(configId: String) -> ExportedFile? {
        guard let runId else { return nil }
        let rows = rows
        let ctx = EvalTraceExport.Context(appVersion: runner.appVersion, build: runner.build, host: EvalHost.description,
                                          ramBytes: DebugLaunch.ramBytes ?? services.totalRamBytes)
        let slug = configId.replacing("model:", with: "").replacing(/[^A-Za-z0-9._-]/, with: "-")
        return ExportedFile(filename: "\(runId).\(slug).traces.jsonl") {
            Data(EvalTraceExport.jsonl(rows, configId: configId, ctx).utf8)
        }
    }

    /// The results as JSONL or CSV (exportEvalResults): a run just made or one opened from the list.
    func exportFile(jsonl: Bool) -> ExportedFile? {
        guard let runId else { return nil }
        let rows = rows
        return ExportedFile(filename: "\(runId).\(jsonl ? "jsonl" : "csv")") {
            Data((jsonl ? EvalExport.jsonl(rows) : EvalExport.csv(rows)).utf8)
        }
    }

    // MARK: device requests

    /// Checks for a request every 2 s while BOAR is in the foreground (debug builds always, release builds while the
    /// Evaluation screen is open).
    func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        polling?.cancel()
        polling = nil
    }

    private func pollOnce() {
        guard !running, !chatBusy(), let text = runner.takePending() else { return }
        let runner = runner
        let request: EvalRequest
        do {
            request = try DeviceEval.parseRequest(text)
        } catch {
            let message = (error as? EvalRequestError)?.message ?? error.localizedDescription
            runner.writeStatus(DeviceEval.requestId(of: text), [("state", "failed"), ("error", .string("invalid request: \(message)"))])
            return
        }
        let installed = runner.installedModels()
        let installedIds = JSONValue(strings: installed.map(\.id))
        if request.pipeline == "answer" {
            runner.writeStatus(request.requestId, [("state", "failed"), ("error", "this native build runs the legacy pipeline only"), ("installedModels", installedIds)])
            return
        }
        let sets = (try? runner.evalSets()) ?? EvalSets(evalSet: [], extraSets: [])
        // A request may also name bench v0.1 ids or categories.
        let bench = (try? BenchFile.bundled().queries) ?? []
        switch DeviceEval.resolve(request, installed: installed, evalSet: sets.evalSet, adaptiveLabel: EvalRunner.adaptiveLabel,
                                  extraSets: sets.extraSets + bench) {
        case .err(let message):
            runner.writeStatus(request.requestId, [("state", "failed"), ("error", .string(message)), ("installedModels", installedIds)])
        case .ok(let resolvedConfigs, let resolvedQueries):
            // A preset (adam, Nov 14): its level's models (or the request's), styles and passes, its topics' questions and labs.
            var plan: BenchPlan?
            if let preset = request.preset {
                let own = request.models?.isEmpty == false
                    ? resolvedConfigs.compactMap { c -> ModelRef? in if case .model(let id, let label) = c { ModelRef(id: id, label: label) } else { nil } }
                    : nil
                let topics = topicsById.isEmpty ? runner.topics() : topicsById
                switch BenchPresets.plan(preset, installed: installed, topics: topics, sets: sets, models: own) {
                case .err(let message):
                    runner.writeStatus(request.requestId, [("state", "failed"), ("error", .string(message)), ("installedModels", installedIds)])
                    return
                case .ok(let p): plan = p
                }
            }
            let configs = plan?.models.map { EvalConfig.model(modelId: $0.id, label: $0.label) } ?? resolvedConfigs
            let queries = plan?.queries ?? resolvedQueries
            let ids = JSONValue(strings: configs.map(\.id))
            let total = JSONValue(plan?.answers ?? configs.count * queries.count)
            let presetName = plan.map { JSONValue.string($0.preset.name) }
            runner.writeStatus(request.requestId, [("state", "accepted"), ("configs", ids), ("total", total), ("completed", 0), ("installedModels", installedIds),
                                                   ("preset", presetName)])
            let rid = request.requestId
            // The language arm for this run only (t9 0420), back to what users get when it ends.
            AnswerLanguage.arm = request.languageArm ?? 1
            start(configs, queries, setKind: nil, requestId: rid, plan: plan, searchOnly: request.searchOnly == true) { result, error in
                AnswerLanguage.arm = 1
                if let result {
                    runner.writeStatus(rid, [("state", "done"), ("configs", ids), ("total", total), ("completed", JSONValue(result.rows.count)),
                                             ("runId", .string(result.runId)), ("resultPath", .string("Documents/eval/\(result.runId).jsonl")),
                                             ("scorecardPath", .string("Documents/eval/\(result.runId).scorecard.txt")), ("preset", presetName),
                                             ("stopped", .bool(result.stopped)), ("installedModels", installedIds)])
                } else {
                    runner.writeStatus(rid, [("state", "failed"), ("configs", ids), ("total", total), ("completed", JSONValue(self.rows.count)),
                                             ("error", .string(error?.localizedDescription ?? "failed")), ("installedModels", installedIds)])
                }
            }
            // Progress lines while it runs.
            Task { [weak self] in
                while true {
                    guard let self, self.running, self.requestId == rid else { return }
                    if let p = self.progress {
                        runner.writeStatus(rid, [("state", "running"), ("configs", ids), ("total", total), ("completed", JSONValue(self.rows.count)),
                                                 ("current", .string("\(p.config.id) / \(p.query.id)")), ("installedModels", installedIds),
                                                 ("runId", runner.activeRunId.map(JSONValue.string))])
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    #if DEBUG
    /// `-uiDemo -uiScreen evaluation`: a finished run to show (EvalDemo), no model needed.
    func debugShowDemo() {
        guard !running, rows.isEmpty else { return }
        if sets.isEmpty { sets = EvalQuestionSet.bundled() }
        let demo = EvalDemo.run(queries: queries)
        for config in demo.configs {
            if case .model(let id, let label) = config { names[id] = EvalModelName(asset: services.catalog.byId(id), label: label) }
        }
        configs = demo.configs
        selected = Set(demo.configs.map(\.id))
        rows = demo.rows
        runId = demo.rows.first?["runId"]?.stringValue
        savedPath = runId.map { "Documents/eval/\($0).jsonl" }
        resultSetKind = setKind
    }
    #endif
}

private enum EvalError: LocalizedError {
    case answerStillWritten

    var errorDescription: String? { "an answer is still being written" }
}
