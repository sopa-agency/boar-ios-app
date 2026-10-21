import BoarCore
import Foundation

/// Evaluation rows as boar-eval **EvalTrace v1** (protocol 1.0.0, `packages/protocol/src/index.ts`; TRACE-FORMAT.md in the
/// public boar-bench repo): the file `harness/judge.mjs` and `scorers/score.py` read as they are. One file per model,
/// since the judge scores one system per file.
public enum EvalTraceExport {
    public static let protocolVersion = "1.0.0"

    public struct Context: Sendable, Equatable {
        /// "ios-<version>+<build>": the app carries no git sha; the judge's `--system` can relabel it.
        public var commit: String
        public var arm: String
        /// "iPhone14,5 iOS 26.6".
        public var host: String
        public var ramGb: Double

        public init(appVersion: String, build: String, host: String, ramBytes: Int64, arm: String = "ios-native") {
            commit = "ios-\(appVersion)+\(build)"
            self.arm = arm
            self.host = host
            // One decimal, never zero (the schema wants a positive number).
            ramGb = max(0.1, (Double(ramBytes) / 1_073_741_824 * 10).rounded() / 10)
        }
    }

    private static func object(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(Dictionary(pairs, uniquingKeysWith: { $1 })) }

    private static func number(_ v: JSONValue?) -> JSONValue {
        switch v {
        case .int?, .double?: v!
        default: .null
        }
    }

    /// ISO 8601 UTC with milliseconds, from epoch milliseconds.
    static func iso(_ ms: Int64) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    /// The trace's error: failures and cancels count against the app (`judge.mjs --floor-errored`).
    static func error(_ row: JSONValue) -> JSONValue {
        let message = row["errorMessage"]?.stringValue
        switch row["outcome"]?.stringValue {
        case "failure": return object([("code", "device-failure"), ("message", .string(message ?? "outcome failure"))])
        case "cancelled": return object([("code", "cancelled"), ("message", .string(message ?? "stopped before done"))])
        default:
            if row["timedOut"]?.boolValue == true { return object([("code", "timeout"), ("message", .string(message ?? "timed out"))]) }
            return .null
        }
    }

    /// One row → one EvalTrace.
    public static func trace(_ row: JSONValue, _ ctx: Context) -> JSONValue {
        let titles = row["retrievedTitles"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let kept = JSONValue.array(titles.map { object([("title", .string($0)), ("section", .null), ("source", .null), ("similarity", .null)]) })
        let model = row["modelId"]?.stringValue ?? "unknown"
        var versions: [(String, JSONValue)] = [("legacy", "eval-device-native")]
        for (key, field) in [("app", "appVersion"), ("evalSet", "evalSetVersion"), ("configId", "configId"), ("personality", "personalityId"),
                             ("promptFormat", "promptFormat"), ("legacyRunId", "runId"), ("residency", "modelResidency")] {
            if let s = row[field]?.stringValue { versions.append((key, .string(s))) }
        }
        if let m = row["maxTokens"]?.int64Value { versions.append(("maxTokens", .string(String(m)))) }
        if let l = row["modelLoadMs"]?.doubleValue { versions.append(("modelLoadMs", .string(String(Int(l.rounded()))))) }
        let peak = row["peakRssBytes"]?.int64Value
        let tokens = row["tokensGenerated"]?.int64Value ?? 0
        return object([
            ("protocol", .string(protocolVersion)),
            ("runId", .string(row["runId"]?.stringValue ?? "")),
            ("itemId", .string(row["queryId"]?.stringValue ?? "")),
            ("question", .string(row["query"]?.stringValue ?? "")),
            ("engine", object([("commit", .string(ctx.commit)), ("arm", .string(ctx.arm)), ("dirty", false)])),
            ("runtime", object([("adapter", "ios-app"), ("host", .string(ctx.host)), ("model", .string(model)), ("sampler", .object([:])),
                                ("versions", object(versions))])),
            ("config", object([("commit", .string(ctx.commit)), ("arm", .string(ctx.arm)), ("modelId", .string(model)), ("settings", .object([:])),
                               ("kit", .array([])), ("device", object([("platform", "ios"), ("ramGb", .double(ctx.ramGb))]))])),
            ("route", object([("task", row["taskType"]?.stringValue.map(JSONValue.string) ?? .null), ("tier", .null), ("outcome", .null),
                              ("reasonCodes", .array(row["reasonCodes"]?.arrayValue ?? []))])),
            ("retrieval", object([("raw", kept), ("kept", kept), ("dropped", .array([]))])),
            ("answer", object([("text", .string(row["answer"]?.stringValue ?? "")), ("cited", .array([])), ("shown", JSONValue(strings: titles)),
                               ("declined", false), ("weakSources", false), ("warnings", .array([]))])),
            ("timing", object([("ttftMs", number(row["ttftMs"])), ("totalMs", number(row["totalLatencyMs"])),
                               ("retrievalMs", number(row["retrievalMs"])), ("prefillMs", number(row["promptMs"])),
                               ("decodeTokPerSec", tokens > 0 ? number(row["tokPerSec"]) : .null),
                               ("promptTokens", number(row["promptTokens"])), ("outputTokens", .int(tokens))])),
            ("resources", peak.map { object([("peakRssMb", .double(Double($0) / 1_048_576)), ("thermal", .null), ("sustainedRatio", .null)]) } ?? .null),
            ("events", .array([])),
            ("error", error(row)),
            ("createdAt", .string(iso(row["createdAt"]?.int64Value ?? 0))),
        ])
    }

    /// The rows of one config as JSONL (one trace per line, keys sorted).
    public static func jsonl(_ rows: [JSONValue], configId: String, _ ctx: Context) -> String {
        rows.filter { $0["configId"]?.stringValue == configId }.map { trace($0, ctx).jsonString + "\n" }.joined()
    }
}
