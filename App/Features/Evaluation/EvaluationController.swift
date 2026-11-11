import BoarAnswer
import BoarCore
import Foundation
import Observation

/// The Evaluation screen's state (port of android `EvaluationViewModel`, extended with the public bench v0.1 sets,
/// docs/BENCHMARK-SCREEN.md): a question set against the chosen models, graded offline as it runs, saved after each answer
/// and shared as judge-ready traces, JSONL or CSV. Also answers device requests a connected computer leaves in
/// `Documents/eval/requests/pending.json` (DeviceEvalRunner's polling), and shows their progress here.
@MainActor
@Observable
final class EvaluationController {
    private(set) var configs: [EvalConfig]?
    var selected: Set<String> = []
    /// Quick check, Research bench v0.1 and the App smoke set.
    private(set) var sets: [EvalQuestionSet] = []
    var setKind: EvalQuestionSet.Kind = .quick
    /// The set the shown results came from.
    private(set) var resultSetKind: EvalQuestionSet.Kind?
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

    @ObservationIgnored let runner: EvalRunner
    @ObservationIgnored private let services: BoarServices
    /// The chat is answering: an evaluation would fight it for the model and memory.
    @ObservationIgnored var chatBusy: @MainActor () -> Bool = { false }
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// Plain names per model id ("Fast" + "Qwen2.5-1.5B-Instruct").
    @ObservationIgnored private var names: [String: EvalModelName] = [:]

    init(services: BoarServices) {
        self.services = services
        runner = EvalRunner(services: services)
    }

    var appVersion: String { runner.appVersion }

    var questionSet: EvalQuestionSet? { sets.first { $0.kind == setKind } ?? sets.first }
    var queries: [EvalQuery] { questionSet?.queries ?? [] }

    /// Per-model and per-category numbers of the shown results.
    var summary: EvalSummary { EvalSummary(rows: rows) }

    func load() {
        guard configs == nil else { return }
        if sets.isEmpty { sets = EvalQuestionSet.bundled() }
        let models = runner.installedModels()
        for m in models {
            names[m.id] = EvalModelName(asset: services.catalog.byId(m.id), label: m.label)
        }
        configs = models.map { EvalConfig.model(modelId: $0.id, label: $0.label) }
        selected = Set(configs?.map(\.id) ?? [])
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

    var chosen: [EvalConfig] { (configs ?? []).filter { selected.contains($0.id) } }

    func run() {
        let chosen = chosen
        guard !running, !chosen.isEmpty, !chatBusy() else { return }
        start(chosen, queries, setKind: setKind, requestId: nil)
    }

    func stop() {
        stopping = true
        runner.stop()
    }

    private func start(_ configs: [EvalConfig], _ queries: [EvalQuery], setKind: EvalQuestionSet.Kind?, requestId: String?,
                       onDone: (@MainActor (EvalRunner.RunResult?, Error?) -> Void)? = nil) {
        running = true
        resultSetKind = setKind
        stopping = false
        rows = []
        runId = nil
        savedPath = nil
        stopped = false
        error = nil
        self.requestId = requestId
        // A long run with the phone on the desk: the screen stays on (keepScreenOn).
        Platform.keepAwake(true)
        let runner = runner
        let services = services
        Task {
            // One model in memory at a time: the chat's is reloaded on its next message.
            await services.host.unload()
            var result: EvalRunner.RunResult?
            var failure: Error?
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try await runner.runConfigs(configs, queries,
                                                onProgress: { p in Task { @MainActor in self.progress = p } },
                                                onRow: { row in Task { @MainActor in self.rows.append(row) } })
                }.value
                if let result {
                    runId = result.runId
                    savedPath = "Documents/eval/\(result.file.lastPathComponent)"
                    stopped = result.stopped
                    rows = result.rows
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

    func exportFile(jsonl: Bool) -> ExportedFile? {
        guard let runId else { return nil }
        let rows = rows
        return ExportedFile(filename: "\(runId).\(jsonl ? "jsonl" : "csv")") {
            Data((jsonl ? rows.map(\.jsonString).joined(separator: "\n") : EvalRunner.toCsv(rows)).utf8)
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
        case .ok(let configs, let queries):
            let ids = JSONValue(strings: configs.map(\.id))
            let total = JSONValue(configs.count * queries.count)
            runner.writeStatus(request.requestId, [("state", "accepted"), ("configs", ids), ("total", total), ("completed", 0), ("installedModels", installedIds)])
            let rid = request.requestId
            start(configs, queries, setKind: nil, requestId: rid) { result, error in
                if let result {
                    runner.writeStatus(rid, [("state", "done"), ("configs", ids), ("total", total), ("completed", JSONValue(result.rows.count)),
                                             ("runId", .string(result.runId)), ("resultPath", .string("Documents/eval/\(result.runId).jsonl")),
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
                                                 ("current", .string("\(p.config.id) / \(p.query.id)")), ("installedModels", installedIds)])
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
