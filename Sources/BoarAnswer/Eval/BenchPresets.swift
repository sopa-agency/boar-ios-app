import BoarCore
import Foundation

/// Bench presets: a level and topics (android engine/eval `BenchPresets.kt`, v2.0.0; adam, Nov 14: "we should have a light
/// benchmark and a long benchmark. this waiting sucks"; "lets create some categories, like fast, only succinct mode.
/// medium, complete. and by topics, like fast plugins, fast problematics"). A preset is named "<level>" or
/// "<level>-<topic>": "fast", "fast-plugins", "medium-research". Without a topic it runs the fixed 17 ("keep those as we
/// have since start"). Pure.
public enum BenchLevel: String, Sendable, CaseIterable, Equatable {
    /// Succinct on the 1.7B (or the only answer model installed): about 9 s a question on the F3.
    case fast
    /// Succinct on both models: about 36 s a question.
    case medium
    /// Succinct and Detailed on both models, and Deep Research for a topic that asks for it: about 3.9 min a question.
    case complete

    public var id: String { rawValue }

    public static func of(_ id: String?) -> BenchLevel? { allCases.first { $0.id == id } }
}

/// One way every question is answered in a run: a style, through Deep Research or not.
public struct BenchPass: Sendable, Equatable {
    public static let pathDeep = "deep"

    public var style: String
    public var deep: Bool

    public init(_ style: String, deep: Bool = false) { self.style = style; self.deep = deep }

    /// "succinct", "detailed", "deep".
    public var key: String { deep ? Self.pathDeep : style }
}

public struct BenchPreset: Sendable, Equatable {
    public var level: BenchLevel
    public var topics: [String]

    public init(_ level: BenchLevel, _ topics: [String]) { self.level = level; self.topics = topics }

    public var name: String { ([level.id] + topics.filter { $0 != BenchPresets.core }).joined(separator: "-") }
}

/// What a preset runs: its models, its passes, its questions (each with its topic), and the labs it switches on.
public struct BenchPlan: Sendable, Equatable {
    public var preset: BenchPreset
    public var models: [ModelRef]
    public var passes: [BenchPass]
    public var queries: [EvalQuery]
    /// queryId -> topic id.
    public var topicOf: [String: String]
    /// The questions each pass runs (`BenchPass.key` -> ids); a Deep Research pass runs only its topic's.
    public var passQueries: [String: [String]]
    public var labs: [String]?

    /// Answers the run will write.
    public var answers: Int { models.count * passes.reduce(0) { $0 + (passQueries[$1.key]?.count ?? 0) } }
}

public enum BenchPresets {
    /// The fixed 17, as a topic: a level alone runs them.
    public static let core = "core"
    public static let smallModel = "qwen3-1.7b-q4km"
    public static let largeModel = "qwen3-4b-instruct-2507-q4km"

    private struct Seed: Hashable { let model: String; let style: String }

    /// Seconds a question on the F3 when no run of the level is on the phone yet: the Cards runs' medians (t9, Nov 14, 14
    /// questions): Succinct 8.9 s on the 1.7B and 26.8 s on the 4B; Detailed 46.3 s and 150.7 s.
    private static let seedSeconds: [Seed: Double] = [
        Seed(model: smallModel, style: "succinct"): 8.9, Seed(model: largeModel, style: "succinct"): 26.8,
        Seed(model: smallModel, style: "detailed"): 46.3, Seed(model: largeModel, style: "detailed"): 150.7,
    ]

    public static func seedSeconds(_ model: String, _ style: String) -> Double? { seedSeconds[Seed(model: model, style: style)] }

    /// "fast" or "fast-plugins" (a topic id may hold dashes); nil for anything else.
    public static func parse(_ name: String) -> BenchPreset? {
        guard let level = BenchLevel.allCases.first(where: { name == $0.id || name.hasPrefix($0.id + "-") }) else { return nil }
        var topic = String(name.dropFirst(level.id.count))
        if topic.hasPrefix("-") { topic.removeFirst() }
        return BenchPreset(level, topic.isEmpty ? [core] : topic.split(separator: "+", omittingEmptySubsequences: false).map(String.init))
    }

    /// The level's models among `installed` (catalog order): fast takes the 1.7B, else the only one, else the first;
    /// medium and complete take the 1.7B and the 4B, filled up to two from the others when one is missing.
    public static func models(_ level: BenchLevel, installed: [ModelRef]) -> [ModelRef] {
        let small = installed.first { $0.id == smallModel }
        let large = installed.first { $0.id == largeModel }
        if level == .fast { return [small ?? installed.first].compactMap { $0 } }
        let both = [small, large].compactMap { $0 }
        return Array((both + installed.filter { !both.contains($0) }).prefix(2))
    }

    public static func passes(_ level: BenchLevel, deepTopic: Bool) -> [BenchPass] {
        switch level {
        case .fast, .medium: [BenchPass("succinct")]
        case .complete: [BenchPass("succinct"), BenchPass("detailed")] + (deepTopic ? [BenchPass("detailed", deep: true)] : [])
        }
    }

    public enum Planned: Sendable, Equatable {
        case ok(BenchPlan)
        case err(String)

        public var plan: BenchPlan? { if case .ok(let p) = self { p } else { nil } }
        public var error: String? { if case .err(let e) = self { e } else { nil } }
    }

    /// The plan for `preset`. `topics`: every topic file the app has, by id. `models`: the request's own models, over the
    /// level's. `labs`: the request's labs, over the topics'.
    public static func plan(_ preset: BenchPreset, installed: [ModelRef], topics: [String: BenchTopic], sets: EvalSets,
                            models: [ModelRef]? = nil, labs: [String]? = nil) -> Planned {
        var chosen: [BenchTopic] = []
        for id in preset.topics {
            guard let t = topics[id] else { return .err("unknown topic \"\(id)\" (\(topics.keys.sorted().joined(separator: ", ")))") }
            chosen.append(t)
        }
        let picked = models ?? Self.models(preset.level, installed: installed)
        if picked.isEmpty { return .err("no answer model installed") }
        var topicOf: [String: String] = [:]
        var queries: [EvalQuery] = []
        for t in chosen {
            let qs: [EvalQuery]
            do { qs = try t.queries(sets) } catch { return .err((error as? BenchTopic.BadTopic)?.message ?? "bad topic \(t.id)") }
            for q in qs where topicOf[q.id] == nil {
                topicOf[q.id] = t.id
                queries.append(q)
            }
        }
        let deepIds = queries.filter { q in chosen.first { $0.id == topicOf[q.id] }?.deepResearch == true }.map(\.id)
        let passes = passes(preset.level, deepTopic: !deepIds.isEmpty)
        var passQueries: [String: [String]] = [:]
        for p in passes { passQueries[p.key] = p.deep ? deepIds : queries.map(\.id) }
        let topicLabs = chosen.compactMap(\.labs)
        var labsOut: [String]? = labs
        if labsOut == nil && !topicLabs.isEmpty {
            var seen = Set<String>()
            labsOut = topicLabs.flatMap { $0 }.filter { seen.insert($0).inserted }
        }
        return .ok(BenchPlan(preset: preset, models: picked, passes: passes, queries: queries, topicOf: topicOf, passQueries: passQueries, labs: labsOut))
    }

    /// A run's expected length: `seconds` known, plus `untimed` Deep Research answers nobody has timed yet.
    public struct Estimate: Sendable, Equatable {
        public var seconds: Double
        public var untimed: Int
        public var fromPrevious: Bool
    }

    /// Before a run starts (adam, Nov 14: "this waiting sucks"): per model and pass, the median whole answer of the last
    /// run of the same level when it has rows for them, else the seed (a model not there counts as the 4B).
    public static func estimate(_ plan: BenchPlan, previousRows: [JSONValue]? = nil) -> Estimate {
        var seconds = 0.0
        var untimed = 0
        var fromPrevious = false
        for m in plan.models {
            for p in plan.passes {
                let n = Double(plan.passQueries[p.key]?.count ?? 0)
                let measured = previousRows.flatMap { rows in
                    EvalScore.median(rows.filter { r in
                        r.str("modelId") == m.id && passKey(r) == p.key && r.str("outcome") == "success"
                    }.compactMap { $0.num("totalLatencyMs") })
                }
                if let measured {
                    seconds += n * measured / 1000
                    fromPrevious = true
                } else if p.deep {
                    untimed += Int(n)
                } else {
                    seconds += n * (seedSeconds(m.id, p.style) ?? seedSeconds(largeModel, p.style) ?? seedSeconds(largeModel, "detailed")!)
                }
            }
        }
        return Estimate(seconds: seconds, untimed: untimed, fromPrevious: fromPrevious)
    }

    /// A row's pass: "deep" for Deep Research, else its style ("succinct"; the default style when it says none).
    public static func passKey(_ row: JSONValue) -> String {
        row.str("path") == BenchPass.pathDeep ? BenchPass.pathDeep : row.str("style") ?? "detailed"
    }
}

extension JSONValue {
    /// A string member (Kotlin `JsonObject.str`: only a JSON string).
    func str(_ k: String) -> String? { self[k]?.stringValue }

    /// A finite number member (Kotlin `JsonObject.num`: `doubleOrNull`, finite).
    func num(_ k: String) -> Double? {
        guard let d = self[k]?.doubleValue, d.isFinite else { return nil }
        return d
    }

    /// A list of strings (Kotlin `JsonObject.list`: the primitives' content).
    func list(_ k: String) -> [String] {
        (self[k]?.arrayValue ?? []).compactMap { v in
            switch v {
            case .string(let s): s
            case .int(let i): String(i)
            case .bool(let b): String(b)
            case .double(let d): String(d)
            default: nil
            }
        }
    }
}
