import BoarAnswer
import BoarCore
import BoarLlama
import BoarModels
import BoarRouting
import Foundation
import os

/// The iOS side of scripts/eval-device.mjs (port of android `DeviceEvalRunner.kt`, byte-compatible requests and rows):
/// takes `Documents/eval/requests/pending.json`, reports in `<requestId>.status.json`, writes `Documents/eval/<runId>.jsonl`
/// and `.run.json`. Runs the legacy pipeline (the fixed-model answer path); adaptive routing and the "answer" pipeline
/// are reported as not supported yet, as on Android. `runConfigs` also backs the Evaluation screen.
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
    }

    static let adaptiveLabel = "Adaptive routing"
    private static let log = BoarLog.logger("eval")

    let services: BoarServices
    let evalDir: URL
    private let requestsDir: URL
    private let stopRequested = StopFlag()
    private let running = OSAllocatedUnfairLock<LlamaSession?>(initialState: nil)
    /// The app version on every row, so a saved or exported run says which build answered.
    let appVersion: String
    /// CFBundleVersion, for the exported traces' engine label.
    let build: String

    init(services: BoarServices) {
        self.services = services
        let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        evalDir = docs.appending(path: "eval", directoryHint: .isDirectory)
        requestsDir = evalDir.appending(path: "requests", directoryHint: .isDirectory)
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Installed language models from the catalog, in catalog order.
    func installedModels() -> [ModelRef] {
        services.catalog.models.filter { $0.kind == .llm && services.isPresent($0) }.map { ModelRef(id: $0.id, label: $0.label) }
    }

    func evalSets() throws -> EvalSets { try EvalSets.bundled() }

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
    /// (evalHarness.runEvaluation).
    func runConfigs(_ configs: [EvalConfig], _ queries: [EvalQuery], onProgress: @escaping @Sendable (Progress) -> Void,
                    onRow: @escaping @Sendable (JSONValue) -> Void) async throws -> RunResult {
        stopRequested.set(false)
        let runId = DeviceEval.newRunId()
        try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
        let rowsFile = evalDir.appending(path: "\(runId).jsonl")
        let runFile = evalDir.appending(path: "\(runId).run.json")
        var rows: [JSONValue] = []
        let personalities = try Personalities.bundled()
        let personalityId = personalities.defaultId
        let systemPrompt = personalities.get(personalityId).systemPrompt
        let maxTokens = personalities.defaultMaxTokens
        // The same Auto engine settings as Android's runner (EngineTweaks()), not the user's Advanced tweaks.
        let params = EngineTweaks().resolve(services.topology, totalRamBytes: services.totalRamBytes).params

        configLoop: for (ci, config) in configs.enumerated() {
            var session: LlamaSession?
            var loaded = false
            var loadMs = 0.0
            var residency = "cold"
            defer { if let s = session { Task { await s.close() } } }
            for (qi, q) in queries.enumerated() {
                if stopRequested.value { break configLoop }
                onProgress(Progress(configIndex: ci, configCount: configs.count, queryIndex: qi, queryCount: queries.count, config: config, query: q))
                let run = Self.object([("runId", .string(runId)), ("configs", JSONValue(strings: configs.map(\.id))),
                                       ("queries", JSONValue(strings: queries.map(\.id))), ("current", .string("\(config.id) / \(q.id)"))])
                try? Data(run.jsonString.utf8).write(to: runFile, options: .atomic)
                let row: JSONValue
                switch config {
                case .adaptive:
                    row = failureRow(runId, config, q, personalityId, maxTokens, "adaptive routing is not in the native build yet")
                case .model(let modelId, _):
                    if !loaded {
                        loaded = true
                        let start = ContinuousClock.now
                        if let asset = services.catalog.byId(modelId), services.isPresent(asset) {
                            session = try? await LlamaSession.load(path: services.fileOf(asset).path(percentEncoded: false), params: params)
                        }
                        loadMs = Self.ms(start.duration(to: .now))
                    } else {
                        residency = "resident"
                        loadMs = 0
                    }
                    if let s = session {
                        running.withLock { $0 = s }
                        var r = await answerRow(s, runId: runId, config: config, modelId: modelId, q: q, personalityId: personalityId,
                                                systemPrompt: systemPrompt, maxTokens: maxTokens, residency: residency, loadMs: loadMs)
                        running.withLock { $0 = nil }
                        if stopRequested.value, case .object(var o) = r {
                            o["outcome"] = .string("cancelled")
                            r = .object(o)
                        }
                        row = r
                    } else {
                        row = failureRow(runId, config, q, personalityId, maxTokens, "model failed to load")
                    }
                }
                let checked = Self.withCheck(row, q)
                rows.append(checked)
                try? Data(rows.map { $0.jsonString + "\n" }.joined().utf8).write(to: rowsFile, options: .atomic)
                onRow(checked)
                Self.log.info("[EVAL] \(q.id, privacy: .public): \(checked["outcome"]?.stringValue ?? "?", privacy: .public) \(checked["check"]?.stringValue ?? "-", privacy: .public)")
            }
            if let s = session {
                session = nil
                await s.close()
            }
        }
        try? FileManager.default.removeItem(at: runFile)
        return RunResult(runId: runId, rows: rows, file: rowsFile, stopped: stopRequested.value)
    }

    private func answerRow(_ s: LlamaSession, runId: String, config: EvalConfig, modelId: String, q: EvalQuery, personalityId: String,
                           systemPrompt: String, maxTokens: Int, residency: String, loadMs: Double) async -> JSONValue {
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
            for try await e in pipeline.answer(AnswerRequest(query: q.query, systemPrompt: systemPrompt, styleReminder: nil, maxTokens: maxTokens)) {
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
        let answer = done?.text ?? ""
        let ttftMs = genStart.map { Self.ms($0.duration(to: firstToken ?? end)) }
        let genLatency = (genStart != nil && ttftMs != nil) ? Self.ms(genStart!.duration(to: end)) - ttftMs! : nil
        let outcome = failure != nil ? "failure" : (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "failure" : "success")
        let m = done?.metrics
        let titles = done?.sources.map(\.title) ?? []
        let taskType = done?.taskType ?? Classify.classifyTask(q.query).value
        let retrieve = !(TaskType(rawValue: taskType).map(Classify.isRetrievalIrrelevant) ?? false)
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
            ("timedOut", .bool(false)), ("createdAt", .int(Self.nowMs())), ("engine", .string("native")),
            ("appVersion", .string(appVersion)),
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

    /// evalRowsToCsv: Android's columns, then the bench check's; arrays joined with "|".
    static let csvColumns = ["runId", "evalSetVersion", "configId", "configLabel", "routingPreset", "personalityId", "maxTokens",
                             "queryId", "category", "query", "modelId", "promptFormat", "taskType", "adaptiveRoutingUsed", "retrievalUsed",
                             "retrievedTitles", "expectedKbTitles", "expectedKbHit", "reasonCodes", "modelSwitches", "crossMessageModelSwitch",
                             "modelResidency", "modelLoadMs", "ttftMs", "retrievalMs", "contextTokensBefore", "contextTokensAfter",
                             "generationLatencyMs", "promptTokens", "promptMs", "cachedTokens", "predictedTokens", "predictedMs", "totalLatencyMs",
                             "tokensGenerated", "tokPerSec", "peakRssBytes", "outcome", "errorMessage", "timedOut", "answer", "createdAt", "appVersion",
                             "benchSet", "gradingType", "check", "checkWhy", "checkPassed", "sourceHit", "referenceTitles"]

    static func toCsv(_ rows: [JSONValue]) -> String {
        ([csvColumns.joined(separator: ",")] + rows.map { r in csvColumns.map { csvCell(r[$0]) }.joined(separator: ",") }).joined(separator: "\n")
    }

    private static func csvCell(_ v: JSONValue?) -> String {
        let s: String
        switch v {
        case nil, .null?: return ""
        case .array(let items)?: s = items.map(cellText).joined(separator: "|")
        case let other?: s = cellText(other)
        }
        return s.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// String(value) for a JSON value: whole numbers without ".0", as JavaScript prints them.
    private static func cellText(_ v: JSONValue) -> String {
        switch v {
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): d.isFinite && d == d.rounded() && abs(d) < 1e21 ? String(Int64(d)) : String(d)
        case .bool(let b): b ? "true" : "false"
        case .null: "null"
        default: v.jsonString
        }
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
