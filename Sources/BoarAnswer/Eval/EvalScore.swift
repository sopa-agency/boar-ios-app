import BoarCore
import Foundation

/// Score v1 for one model's answers in an evaluation run (android EvalScore.kt, a port of src/eval/score.pure.ts;
/// docs/RESULTS_SCORE.md): speed 60 %, reliability 25 %, sources found 15 %. It measures speed and reliability on this
/// phone, not whether the answers are right. Computed on the phone from the run's rows; nothing is sent.
public enum EvalScore {
    public static let scoreVersion = 1
    /// Decode speed that earns the full speed part: about three times reading speed.
    public static let referenceTokPerSec = 20.0
    /// Shorter answers are mostly prefill and say little about decode speed.
    public static let minTokensForSpeed = 16.0
    public static let wSpeed = 0.6
    public static let wReliability = 0.25
    public static let wRetrieval = 0.15
    /// Below this share of completed answers the score is 0: a fast model that fails isn't a pick.
    public static let minReliability = 0.5

    /// The fields of a result row the score reads.
    public struct Row: Sendable, Equatable {
        public var configId: String
        public var configLabel: String?
        public var modelId: String?
        public var outcome: String?
        public var timedOut = false
        public var tokensGenerated: Double?
        public var tokPerSec: Double?
        public var ttftMs: Double?
        public var totalLatencyMs: Double?
        public var expectedKbHit: Bool?
        public var peakRssBytes: Double?

        public init(configId: String, configLabel: String? = nil, modelId: String? = nil, outcome: String? = nil,
                    timedOut: Bool = false, tokensGenerated: Double? = nil, tokPerSec: Double? = nil, ttftMs: Double? = nil,
                    totalLatencyMs: Double? = nil, expectedKbHit: Bool? = nil, peakRssBytes: Double? = nil) {
            self.configId = configId; self.configLabel = configLabel; self.modelId = modelId; self.outcome = outcome
            self.timedOut = timedOut; self.tokensGenerated = tokensGenerated; self.tokPerSec = tokPerSec; self.ttftMs = ttftMs
            self.totalLatencyMs = totalLatencyMs; self.expectedKbHit = expectedKbHit; self.peakRssBytes = peakRssBytes
        }

        public var completed: Bool { outcome == "success" && !timedOut }

        /// A runner row: strings only from JSON strings, numbers only when finite, as Kotlin's `Row.of`. A research bench
        /// row says whether its reference article was found as `sourceHit` (Bench), read when `expectedKbHit` is absent.
        public init(_ o: JSONValue) {
            func num(_ k: String) -> Double? { o[k]?.doubleValue.flatMap { $0.isFinite ? $0 : nil } }
            self.init(configId: o["configId"]?.stringValue ?? "", configLabel: o["configLabel"]?.stringValue,
                      modelId: o["modelId"]?.stringValue, outcome: o["outcome"]?.stringValue,
                      timedOut: o["timedOut"]?.boolValue == true, tokensGenerated: num("tokensGenerated"),
                      tokPerSec: num("tokPerSec"), ttftMs: num("ttftMs"), totalLatencyMs: num("totalLatencyMs"),
                      expectedKbHit: o["expectedKbHit"]?.boolValue ?? o["sourceHit"]?.boolValue, peakRssBytes: num("peakRssBytes"))
        }
    }

    public struct ModelScore: Sendable, Equatable, Identifiable {
        public var configId: String
        public var modelId: String?
        public var modelLabel: String?
        public var answers: Int
        public var completed: Int
        public var retrievalQuestions: Int
        public var retrievalHits: Int
        public var medianTokPerSec: Double?
        public var medianTtftMs: Double?
        public var medianTotalMs: Double?
        public var peakRssBytes: Double?
        /// 0-1 parts; `retrieval` is nil when no question expected an article.
        public var speed: Double
        public var reliability: Double
        public var retrieval: Double?
        /// 0-100.
        public var score: Int
        public var id: String { configId }
    }

    /// Continuous median, like Postgres's percentile_cont(0.5).
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = Double(s.count - 1) / 2
        return (s[Int(mid.rounded(.down))] + s[Int(mid.rounded(.up))]) / 2
    }

    /// Math.round in JS (and Kotlin's roundToInt) rounds .5 up; for these positive values `.rounded()` does the same.
    public static func scoreParts(speed: Double, reliability: Double, retrieval: Double?) -> Int {
        if reliability < minReliability { return 0 }
        guard let retrieval else {
            let rest = wSpeed + wReliability
            return Int((100 * ((wSpeed / rest) * speed + (wReliability / rest) * reliability)).rounded())
        }
        return Int((100 * (wSpeed * speed + wReliability * reliability + wRetrieval * retrieval)).rounded())
    }

    public static func scoreConfig(_ rows: [Row]) -> ModelScore {
        let done = rows.filter(\.completed)
        let withExpected = rows.filter { $0.expectedKbHit != nil }
        let hits = withExpected.count { $0.expectedKbHit == true }
        let medianTokPerSec = median(done.filter { ($0.tokensGenerated ?? 0) >= minTokensForSpeed && ($0.tokPerSec ?? 0) > 0 }
            .compactMap(\.tokPerSec))
        let speed = min(1, (medianTokPerSec ?? 0) / referenceTokPerSec)
        let reliability = rows.isEmpty ? 0 : Double(done.count) / Double(rows.count)
        let retrieval = withExpected.isEmpty ? nil : Double(hits) / Double(withExpected.count)
        return ModelScore(
            configId: rows.first?.configId ?? "",
            modelId: rows.lazy.compactMap(\.modelId).first,
            modelLabel: rows.lazy.compactMap(\.configLabel).first,
            answers: rows.count, completed: done.count,
            retrievalQuestions: withExpected.count, retrievalHits: hits,
            medianTokPerSec: medianTokPerSec,
            medianTtftMs: median(done.compactMap(\.ttftMs)),
            medianTotalMs: median(done.compactMap(\.totalLatencyMs)),
            peakRssBytes: rows.compactMap(\.peakRssBytes).max(),
            speed: speed, reliability: reliability, retrieval: retrieval,
            score: scoreParts(speed: speed, reliability: reliability, retrieval: retrieval)
        )
    }

    /// One score per configuration in the run, best first (stable for ties, as Kotlin's sortedByDescending).
    public static func scoreRun(_ rows: [Row]) -> [ModelScore] {
        var order: [String] = []
        var grouped: [String: [Row]] = [:]
        for r in rows {
            if grouped[r.configId] == nil { order.append(r.configId) }
            grouped[r.configId, default: []].append(r)
        }
        return order.map { scoreConfig(grouped[$0] ?? []) }
            .enumerated().sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
    }

    public static func scoreRun(json rows: [JSONValue]) -> [ModelScore] { scoreRun(rows.map(Row.init)) }
}
