import BoarCore
import Foundation

/// Per-model and per-category numbers of an evaluation run, from its rows (the Benchmark screen's summary and
/// comparison). Deterministic: precheck, source found, speed and memory; no judge.
public struct EvalSummary: Sendable, Equatable {
    public struct Stats: Sendable, Equatable {
        public var answers = 0
        /// outcome "failure" (load failure, error, empty answer).
        public var failed = 0
        public var cancelled = 0
        /// Answers the phone graded with precheck.
        public var checked = 0
        /// precheck pass, or a refusal where declining is allowed.
        public var passed = 0
        /// A forbidden claim matched (precheck "confident-wrong").
        public var wrong = 0
        public var refused = 0
        public var missingFacts = 0
        /// Answers whose item names a reference article, and how many kept it.
        public var sourceItems = 0
        public var sourceHits = 0
        public var totalP50Ms: Double?
        public var totalP90Ms: Double?
        public var ttftP50Ms: Double?
        public var tokPerSecMedian: Double?
        public var peakBytes: Int64?
        public var loadMs: Double?

        public init() {}

        public var passRate: Double? { checked > 0 ? Double(passed) / Double(checked) : nil }
        public var sourceRate: Double? { sourceItems > 0 ? Double(sourceHits) / Double(sourceItems) : nil }
    }

    public struct Category: Sendable, Equatable, Identifiable {
        public var category: String
        public var stats: Stats
        public var id: String { category }
    }

    public struct Config: Sendable, Equatable, Identifiable {
        public var configId: String
        public var label: String
        public var modelId: String?
        public var overall: Stats
        /// In the order the categories first appear in the rows.
        public var categories: [Category]
        public var id: String { configId }
    }

    /// In the order the configs first appear in the rows.
    public var configs: [Config]

    public init(rows: [JSONValue]) {
        var order: [String] = []
        var grouped: [String: [JSONValue]] = [:]
        for r in rows {
            let id = r["configId"]?.stringValue ?? ""
            if grouped[id] == nil { order.append(id) }
            grouped[id, default: []].append(r)
        }
        configs = order.map { id in
            let rs = grouped[id] ?? []
            var catOrder: [String] = []
            var byCat: [String: [JSONValue]] = [:]
            for r in rs {
                let c = r["category"]?.stringValue ?? ""
                if byCat[c] == nil { catOrder.append(c) }
                byCat[c, default: []].append(r)
            }
            return Config(configId: id, label: rs.first?["configLabel"]?.stringValue ?? id, modelId: rs.first?["modelId"]?.stringValue,
                          overall: Self.stats(rs), categories: catOrder.map { Category(category: $0, stats: Self.stats(byCat[$0] ?? [])) })
        }
    }

    static func stats(_ rows: [JSONValue]) -> Stats {
        var s = Stats()
        var totals: [Double] = [], ttfts: [Double] = [], rates: [Double] = []
        for r in rows {
            s.answers += 1
            switch r["outcome"]?.stringValue {
            case "failure": s.failed += 1
            case "cancelled": s.cancelled += 1
            default: break
            }
            if let check = r["check"]?.stringValue {
                s.checked += 1
                if r["checkPassed"]?.boolValue == true { s.passed += 1 }
                switch Precheck.Status(rawValue: check) {
                case .confidentWrong: s.wrong += 1
                case .refused: s.refused += 1
                case .failMissing: s.missingFacts += 1
                default: break
                }
            }
            if let hit = r["sourceHit"]?.boolValue, r["outcome"]?.stringValue != "cancelled" {
                s.sourceItems += 1
                if hit { s.sourceHits += 1 }
            }
            // Speed only from answers that finished: a failure's or a cancel's time is not an answer's time.
            guard r["outcome"]?.stringValue == "success" else { continue }
            if let t = r["totalLatencyMs"]?.doubleValue { totals.append(t) }
            if let t = r["ttftMs"]?.doubleValue { ttfts.append(t) }
            if let t = r["tokPerSec"]?.doubleValue { rates.append(t) }
            if let p = r["peakRssBytes"]?.int64Value { s.peakBytes = max(s.peakBytes ?? 0, p) }
            if let l = r["modelLoadMs"]?.doubleValue, l > 0 { s.loadMs = max(s.loadMs ?? 0, l) }
        }
        s.totalP50Ms = median(totals)
        s.totalP90Ms = nearestRank(totals, 0.9)
        s.ttftP50Ms = median(ttfts)
        s.tokPerSecMedian = median(rates)
        return s
    }

    /// The middle value; the mean of the two middle values for an even count.
    public static func median(_ xs: [Double]) -> Double? {
        if xs.isEmpty { return nil }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Nearest-rank percentile: the smallest value with at least `p` of the values at or below it.
    public static func nearestRank(_ xs: [Double], _ p: Double) -> Double? {
        if xs.isEmpty { return nil }
        let s = xs.sorted()
        let rank = Int((p * Double(s.count) - 1e-9).rounded(.up))
        return s[min(max(rank, 1), s.count) - 1]
    }
}
