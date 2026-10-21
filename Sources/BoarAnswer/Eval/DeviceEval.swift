import BoarCore
import BoarModels
import BoarRouting
import Foundation

/// One evaluation question (src/eval/evalSet.ts), with the set version its rows record. Bench v0.1 items also carry
/// their grading, danger flag and the Wikipedia titles of their reference sources (docs/BENCHMARK-SCREEN.md).
public struct EvalQuery: Codable, Sendable, Equatable {
    public var id: String
    public var category: String
    public var query: String
    public var expectedKbTitles: [String]
    public var gradingNotes: String
    public var setVersion: String
    public var grading: BenchGrading?
    public var danger: Bool
    public var referenceTitles: [String]

    public init(id: String, category: String, query: String, expectedKbTitles: [String] = [], gradingNotes: String = "", setVersion: String,
                grading: BenchGrading? = nil, danger: Bool = false, referenceTitles: [String] = []) {
        self.id = id; self.category = category; self.query = query
        self.expectedKbTitles = expectedKbTitles; self.gradingNotes = gradingNotes; self.setVersion = setVersion
        self.grading = grading; self.danger = danger; self.referenceTitles = referenceTitles
    }

    private enum CodingKeys: String, CodingKey { case id, category, query, expectedKbTitles, gradingNotes, setVersion, grading, danger, referenceTitles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(String.self, forKey: .category)
        query = try c.decode(String.self, forKey: .query)
        expectedKbTitles = try c.decodeIfPresent([String].self, forKey: .expectedKbTitles) ?? []
        gradingNotes = try c.decodeIfPresent(String.self, forKey: .gradingNotes) ?? ""
        setVersion = try c.decode(String.self, forKey: .setVersion)
        grading = try c.decodeIfPresent(BenchGrading.self, forKey: .grading)
        danger = try c.decodeIfPresent(Bool.self, forKey: .danger) ?? false
        referenceTitles = try c.decodeIfPresent([String].self, forKey: .referenceTitles) ?? []
    }
}

public struct EvalSets: Codable, Sendable, Equatable {
    public var evalSet: [EvalQuery]
    public var extraSets: [EvalQuery]

    public init(evalSet: [EvalQuery], extraSets: [EvalQuery]) { self.evalSet = evalSet; self.extraSets = extraSets }

    public static func parse(_ data: Data) throws -> EvalSets { try JSONDecoder().decode(EvalSets.self, from: data) }

    /// The `eval-set.json` bundled with BoarModels.
    public static func bundled() throws -> EvalSets { try parse(BoarData.data(.evalSet)) }
}

/// A request from scripts/eval-device.mjs (src/eval/deviceEvalRequest.pure.ts EvalRequest).
public struct EvalRequest: Sendable, Equatable {
    public var requestId: String
    public var models: [String]?
    public var adaptive: Bool?
    public var queries: [String]?
    /// "legacy" (default) or "answer".
    public var pipeline: String?
    /// Pipeline "answer" fields, kept as sent: this build runs the legacy pipeline only.
    public var answerOnly: [String: JSONValue]

    public init(requestId: String, models: [String]? = nil, adaptive: Bool? = nil, queries: [String]? = nil, pipeline: String? = nil, answerOnly: [String: JSONValue] = [:]) {
        self.requestId = requestId; self.models = models; self.adaptive = adaptive; self.queries = queries
        self.pipeline = pipeline; self.answerOnly = answerOnly
    }
}

public struct ModelRef: Sendable, Equatable {
    public var id: String
    public var label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public enum EvalConfig: Sendable, Equatable {
    case model(modelId: String, label: String)
    case adaptive(label: String)

    public var label: String {
        switch self {
        case .model(_, let label), .adaptive(let label): label
        }
    }

    /// evalConfigId: "model:<id>" or "adaptive".
    public var id: String {
        switch self {
        case .model(let modelId, _): "model:\(modelId)"
        case .adaptive: "adaptive"
        }
    }
}

public enum EvalResolution: Sendable, Equatable {
    case ok(configs: [EvalConfig], queries: [EvalQuery])
    case err(String)
}

/// A request that does not parse; `message` is the TypeScript's text.
public struct EvalRequestError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The device evaluation protocol's logic, ported from deviceEvalRequest.pure.ts and evalHarness.pure.ts (golden tests).
public enum DeviceEval {
    private static let requestIdPattern = Rx("^[a-z0-9][a-z0-9-]{0,63}\\z")
    private static let setVersionPattern = Rx("^[A-Za-z0-9_.-]{1,64}\\z")
    private static let answerOnlyKeys = ["questions", "answerAnyway", "evalSetVersion", "install", "answerSettings", "confirmLargeModels"]

    private static func stringList(_ value: JSONValue?, _ field: String) throws -> [String]? {
        guard let value else { return nil }
        guard case .array(let items) = value, items.allSatisfy({ if case .string(let s) = $0 { return !JsString.trim(s).isEmpty } else { return false } }) else {
            throw EvalRequestError("\"\(field)\" must be a list of non-empty strings")
        }
        return items.map { JsString.trim($0.stringValue ?? "") }
    }

    private static func isBool(_ v: JSONValue?) -> Bool {
        if case .bool = v { return true }
        return false
    }

    /// parseEvalRequest; throws `EvalRequestError` with the TS message. Answer-pipeline fields are checked lightly.
    public static func parseRequest(_ text: String) throws -> EvalRequest {
        guard let raw = JSONValue(jsonString: text) else { throw EvalRequestError("invalid JSON") }
        // typeof [] is "object" in JavaScript: an array passes this check and fails on its missing requestId.
        if case .array = raw { throw EvalRequestError("requestId must be 1-64 lowercase letters, digits or dashes") }
        guard case .object(let o) = raw else { throw EvalRequestError("request must be a JSON object") }
        // A JSON null member counts as present (a Kotlin JsonNull is not null), so it fails its type check below.
        func member(_ k: String) -> JSONValue? { o[k] }
        guard let id = member("requestId")?.stringValue, requestIdPattern.containsMatch(in: id) else {
            throw EvalRequestError("requestId must be 1-64 lowercase letters, digits or dashes")
        }
        if member("adaptive") != nil && !isBool(member("adaptive")) { throw EvalRequestError("\"adaptive\" must be a boolean") }
        let pipelineValue = member("pipeline")
        let pipe = pipelineValue?.stringValue
        if pipelineValue != nil && pipe != "legacy" && pipe != "answer" { throw EvalRequestError("\"pipeline\" must be \"legacy\" or \"answer\"") }
        let present = answerOnlyKeys.filter { member($0) != nil }
        if member("confirmLargeModels") != nil && !isBool(member("confirmLargeModels")) { throw EvalRequestError("\"confirmLargeModels\" must be a boolean") }
        if pipe != "answer" && !present.isEmpty { throw EvalRequestError("\(present.joined(separator: ", ")) need \"pipeline\": \"answer\"") }
        if member("answerAnyway") != nil && !isBool(member("answerAnyway")) { throw EvalRequestError("\"answerAnyway\" must be a boolean") }
        if let v = member("evalSetVersion") {
            guard let s = v.stringValue, setVersionPattern.containsMatch(in: s) else {
                throw EvalRequestError("\"evalSetVersion\" must be 1-64 letters, digits, dots, dashes or underscores")
            }
        }
        var adaptive: Bool?
        if case .bool(let b) = member("adaptive") { adaptive = b }
        return EvalRequest(
            requestId: id, models: try stringList(member("models"), "models"), adaptive: adaptive,
            queries: try stringList(member("queries"), "queries"), pipeline: pipe,
            answerOnly: Dictionary(uniqueKeysWithValues: present.map { ($0, o[$0]!) })
        )
    }

    private static let requestIdScan = Rx("\"requestId\"\(JsString.ws)*:\(JsString.ws)*\"([a-z0-9-]{1,64})\"")

    /// The request id even from a request that failed to parse, for its "failed" status.
    public static func requestId(of text: String) -> String {
        requestIdScan.firstMatch(in: text)?.group(1, in: text) ?? "invalid"
    }

    private static let notAlnum = Rx("[^a-z0-9]")
    private static func normalize(_ s: String) -> String { notAlnum.replace(s.lowercased(), with: "") }

    /// matchModels: an exact id, else every installed model whose id or label contains the selector.
    public static func matchModels(_ selector: String, installed: [ModelRef]) -> [ModelRef] {
        let exact = installed.filter { $0.id == selector }
        if !exact.isEmpty { return exact }
        let needle = normalize(selector)
        // Kotlin `contains("")` is true for any text.
        return installed.filter { needle.isEmpty || normalize($0.id).contains(needle) || normalize($0.label).contains(needle) }
    }

    /// resolveEvalRequest: no models and no adaptive flag means every installed model plus adaptive.
    public static func resolve(
        _ request: EvalRequest, installed: [ModelRef], evalSet: [EvalQuery], adaptiveLabel: String, extraSets: [EvalQuery] = []
    ) -> EvalResolution {
        let everything = (request.models ?? []).isEmpty && request.adaptive != true
        var models: [ModelRef] = everything ? installed : []
        if !everything {
            for selector in request.models ?? [] {
                let matches = matchModels(selector, installed: installed)
                if matches.count != 1 {
                    let detail = matches.isEmpty ? "matches no installed model" : "is ambiguous (\(matches.map(\.id).joined(separator: ", ")))"
                    return .err("model \"\(selector)\" \(detail)")
                }
                if !models.contains(where: { $0.id == matches[0].id }) { models.append(matches[0]) }
            }
        }
        var configs: [EvalConfig] = models.map { .model(modelId: $0.id, label: $0.label) }
        if everything || request.adaptive == true { configs.append(.adaptive(label: adaptiveLabel)) }
        var queries = evalSet
        if let wanted = request.queries, !wanted.isEmpty {
            let all = evalSet + extraSets
            let unknown = wanted.filter { s in !all.contains(where: { $0.id == s || $0.category == s }) }
            if !unknown.isEmpty { return .err("unknown query id or category: \(unknown.joined(separator: ", "))") }
            queries = all.filter { wanted.contains($0.id) || wanted.contains($0.category) }
        }
        return .ok(configs: configs, queries: queries)
    }

    /// buildFixedModelPlan's reason codes.
    public static func fixedPlanReasonCodes(retrieve: Bool, modelId: String) -> [String] {
        ["eval:fixed-model", retrieve ? "retrieve:relevant-to-task" : "retrieve:skipped-task-not-knowledge-based", "generate:fixed-\(modelId)"]
    }

    /// expectedKbHit: nil when nothing is expected, else whether every expected title was retrieved.
    public static func expectedKbHit(_ expected: [String], retrieved: [String]) -> Bool? {
        expected.isEmpty ? nil : expected.allSatisfy(retrieved.contains)
    }

    /// tokensPerSecond (tokens after the first, over the time after it).
    public static func tokensPerSecond(tokens: Int, generationLatencyMs: Double?) -> Double? {
        guard let ms = generationLatencyMs, ms > 0, tokens > 0 else { return nil }
        return Double(tokens) / (ms / 1000)
    }

    /// newEvalRunId: "eval-" + the ISO instant with ':' and '.' as '-'.
    public static func newRunId(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        // Proleptic Gregorian, UTC (days-from-civil inverse), as java.time formats an Instant.
        let msPerDay: Int64 = 86_400_000
        var days = nowMs / msPerDay
        var rem = nowMs % msPerDay
        if rem < 0 { rem += msPerDay; days -= 1 }
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        func p(_ v: Int64, _ w: Int) -> String { let s = String(v); return String(repeating: "0", count: max(0, w - s.count)) + s }
        let h = rem / 3_600_000, mi = rem / 60_000 % 60, s = rem / 1000 % 60, ms = rem % 1000
        return "eval-\(p(year, 4))-\(p(month, 2))-\(p(day, 2))T\(p(h, 2))-\(p(mi, 2))-\(p(s, 2))-\(p(ms, 3))Z"
    }
}
