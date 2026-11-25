import BoarCore
import Foundation

/// What a saved run says about itself, next to its rows as `<runId>.meta.json` (android engine/eval `SavedRuns.kt`, v2.0.0;
/// adam, Nov 14: "i miss a saved benchmark results, like, i run, closed, and now, cant review? where it is saved and i could
/// load it from evaluations").
public struct RunMeta: Codable, Sendable, Equatable, Identifiable {
    public static let stateRunning = "running"
    public static let stateDone = "done"
    public static let stateStopped = "stopped"
    public static let stateFailed = "failed"
    /// A run whose app closed before it ended: "running" on disk, no runner going.
    public static let stateInterrupted = "interrupted"

    public var runId: String
    public var createdAt: Int64
    public var appVersion: String?
    public var models: [String]
    /// nil: a run chosen by hand (models ticked) or one from before presets.
    public var level: String?
    public var topics: [String]
    public var topicVersions: [String: Int]
    /// The passes: "succinct", "detailed", "deep".
    public var passes: [String]
    /// "app" (the Benchmark screen) or "request" (a connected computer's device request; android "adb").
    public var source: String
    public var requestId: String?
    /// running, done, stopped or failed.
    public var state: String
    public var rows: Int
    public var finishedAt: Int64?
    public var error: String?

    public var id: String { runId }

    public init(runId: String, createdAt: Int64, appVersion: String? = nil, models: [String] = [], level: String? = nil, topics: [String] = [],
                topicVersions: [String: Int] = [:], passes: [String] = [], source: String = "app", requestId: String? = nil,
                state: String = RunMeta.stateRunning, rows: Int = 0, finishedAt: Int64? = nil, error: String? = nil) {
        self.runId = runId; self.createdAt = createdAt; self.appVersion = appVersion; self.models = models; self.level = level
        self.topics = topics; self.topicVersions = topicVersions; self.passes = passes; self.source = source; self.requestId = requestId
        self.state = state; self.rows = rows; self.finishedAt = finishedAt; self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case runId, createdAt, appVersion, models, level, topics, topicVersions, passes, source, requestId, state, rows, finishedAt, error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runId = try c.decode(String.self, forKey: .runId)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
        level = try c.decodeIfPresent(String.self, forKey: .level)
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        topicVersions = try c.decodeIfPresent([String: Int].self, forKey: .topicVersions) ?? [:]
        passes = try c.decodeIfPresent([String].self, forKey: .passes) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "app"
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? Self.stateRunning
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        finishedAt = try c.decodeIfPresent(Int64.self, forKey: .finishedAt)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    /// Kotlin `encodeDefaults = true` with explicit nulls, so the file reads the same as Android's.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(runId, forKey: .runId); try c.encode(createdAt, forKey: .createdAt); try c.encode(appVersion, forKey: .appVersion)
        try c.encode(models, forKey: .models); try c.encode(level, forKey: .level); try c.encode(topics, forKey: .topics)
        try c.encode(topicVersions, forKey: .topicVersions); try c.encode(passes, forKey: .passes); try c.encode(source, forKey: .source)
        try c.encode(requestId, forKey: .requestId); try c.encode(state, forKey: .state); try c.encode(rows, forKey: .rows)
        try c.encode(finishedAt, forKey: .finishedAt); try c.encode(error, forKey: .error)
    }
}

/// Every evaluation run kept on the phone, in Documents/eval (nothing leaves it unless shared): the screen's list, opening
/// one, deleting one. Runs from the screen and from device requests are in the same folder, so both are listed. A run from
/// before this change has no meta: what its rows carry stands in (date from its id, build, models).
public struct SavedRunStore: Sendable {
    public let dir: URL

    public init(dir: URL) { self.dir = dir }

    public func rowsFile(_ runId: String) -> URL { dir.appending(path: "\(runId).jsonl") }
    public func metaFile(_ runId: String) -> URL { dir.appending(path: "\(runId).meta.json") }
    private func progressFile(_ runId: String) -> URL { dir.appending(path: "\(runId).run.json") }
    /// The scorecard as text, written at the end of a run.
    public func scorecardFile(_ runId: String) -> URL { dir.appending(path: "\(runId).scorecard.txt") }

    public func writeMeta(_ meta: RunMeta) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? enc.encode(meta) else { return }
        try? data.write(to: metaFile(meta.runId), options: .atomic)
    }

    public func readMeta(_ runId: String) -> RunMeta? {
        guard let data = try? Data(contentsOf: metaFile(runId)) else { return nil }
        return try? JSONDecoder().decode(RunMeta.self, from: data)
    }

    public func rows(_ runId: String) -> [JSONValue] {
        guard let data = try? Data(contentsOf: rowsFile(runId)) else { return [] }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.allSatisfy(\.isWhitespace), let v = JSONValue(jsonString: String(line)), case .object = v else { return nil }
            return v
        }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// Newest first. `active`: the run going now, which stays "running"; any other run still "running" on disk was cut off
    /// by the app closing and is listed as interrupted.
    public func list(active: String? = nil) -> [RunMeta] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
        let ids = names.filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(".jsonl".count)) }
        return ids.map { id in
            var meta = readMeta(id) ?? Self.fromRows(id, rows(id), unfinished: exists(progressFile(id)))
            if meta.state == RunMeta.stateRunning && id != active { meta.state = RunMeta.stateInterrupted }
            return meta
        }.sorted { ($0.createdAt, $0.runId) > ($1.createdAt, $1.runId) }
    }

    /// The last finished run before `run` with its level and topics, to compare with; nil for a run by hand.
    public func previous(_ run: RunMeta, all: [RunMeta]? = nil) -> RunMeta? {
        guard run.level != nil else { return nil }
        return (all ?? list()).first {
            $0.runId != run.runId && $0.level == run.level && $0.topics == run.topics && $0.createdAt < run.createdAt
                && [RunMeta.stateDone, RunMeta.stateStopped].contains($0.state)
        }
    }

    /// The last finished run of `level`, any topics: what the expected time is read from.
    public func lastOfLevel(_ level: String, all: [RunMeta]? = nil) -> RunMeta? {
        (all ?? list()).first { $0.level == level && $0.state == RunMeta.stateDone }
    }

    /// Deletes the run's rows, meta, progress, scorecard and exported traces; true when its rows are gone.
    @discardableResult
    public func delete(_ runId: String) -> Bool {
        let fm = FileManager.default
        for f in [metaFile(runId), progressFile(runId), scorecardFile(runId), dir.appending(path: "\(runId).jsonl.tmp")] { try? fm.removeItem(at: f) }
        let rows = rowsFile(runId)
        if !exists(rows) { return true }
        return (try? fm.removeItem(at: rows)) != nil
    }

    /// "eval-2026-11-14T05-21-00-000Z" -> its time in ms; nil for another name.
    public static func timeOf(_ runId: String) -> Int64? {
        let ns = runId as NSString
        guard let m = runIdPattern.firstMatch(in: runId, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let g = (1...7).map { Int(ns.substring(with: m.range(at: $0)))! }
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (g[0], g[1], g[2], g[3], g[4], g[5])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Instant.parse rejects a day or hour out of range; Calendar would roll it over.
        guard (1...12).contains(g[1]), (1...31).contains(g[2]), g[3] < 24, g[4] < 60, g[5] < 60,
              let date = cal.date(from: c), cal.component(.day, from: date) == g[2] else { return nil }
        return Int64((date.timeIntervalSince1970 * 1000).rounded()) + Int64(g[6])
    }

    private static let runIdPattern = try! NSRegularExpression(pattern: #"^eval-([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})-([0-9]{3})Z$"#)

    /// An old run's meta, from what its rows carry.
    public static func fromRows(_ runId: String, _ rows: [JSONValue], unfinished: Bool = false) -> RunMeta {
        let created = timeOf(runId) ?? rows.lazy.compactMap { $0.num("createdAt").map { Int64($0) } }.first ?? 0
        let state = unfinished ? RunMeta.stateRunning : rows.contains { $0.str("outcome") == "cancelled" } ? RunMeta.stateStopped : RunMeta.stateDone
        func distinct(_ xs: [String]) -> [String] { var seen = Set<String>(); return xs.filter { seen.insert($0).inserted } }
        return RunMeta(runId: runId, createdAt: created, appVersion: rows.lazy.compactMap { $0.str("appVersion") }.first,
                       models: distinct(rows.compactMap { $0.str("modelId") }), level: rows.lazy.compactMap { $0.str("level") }.first,
                       topics: distinct(rows.compactMap { $0.str("topic") }), passes: distinct(rows.map(BenchPresets.passKey)),
                       source: "unknown", state: state, rows: rows.count, finishedAt: rows.compactMap { $0.num("createdAt").map { Int64($0) } }.max())
    }
}

/// Export as JSONL or CSV (exportEvalResults), for a run just made or one opened from the list (android `EvalExport`).
public enum EvalExport {
    /// evalRowsToCsv: Android's columns (with v2.0.0's tool, retrievalMode, style, notFound, level, topic and path), then
    /// the iOS bench check's; arrays joined with "|".
    public static let csvColumns = ["runId", "evalSetVersion", "configId", "configLabel", "routingPreset", "personalityId", "maxTokens",
                                    "queryId", "category", "query", "modelId", "promptFormat", "taskType", "adaptiveRoutingUsed", "retrievalUsed",
                                    "retrievedTitles", "expectedKbTitles", "expectedKbHit", "reasonCodes", "modelSwitches", "crossMessageModelSwitch",
                                    "modelResidency", "modelLoadMs", "ttftMs", "retrievalMs", "contextTokensBefore", "contextTokensAfter",
                                    "generationLatencyMs", "promptTokens", "promptMs", "cachedTokens", "predictedTokens", "predictedMs", "totalLatencyMs",
                                    "tokensGenerated", "tokPerSec", "peakRssBytes", "outcome", "errorMessage", "timedOut", "answer", "createdAt", "appVersion",
                                    "tool", "retrievalMode", "style", "notFound", "level", "topic", "path",
                                    "benchSet", "gradingType", "check", "checkWhy", "checkPassed", "sourceHit", "referenceTitles"]

    public static func jsonl(_ rows: [JSONValue]) -> String { rows.map(\.jsonString).joined(separator: "\n") }

    public static func csv(_ rows: [JSONValue]) -> String {
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
