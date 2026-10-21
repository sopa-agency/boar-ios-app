import BoarCore
import BoarModels
import Foundation

/// The public boar-eval bench v0.1 bundled with BoarModels (`bench-v0.1.json`, written by scripts/build-bench.py from
/// `bench/v0.1/questions.public.jsonl`). Only the public dev split: held-out and blind sets are never bundled.
public struct BenchFile: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public var id: String
        public var category: String
        public var question: String
        public var danger: Bool
        public var grading: BenchGrading
        public var referenceTitles: [String]
    }

    public var bench: String
    public var setVersion: String
    public var sha256: String
    public var gradingVersion: String
    /// The Quick check's item ids, in run order.
    public var quick: [String]
    public var items: [Item]

    public static func parse(_ data: Data) throws -> BenchFile { try JSONDecoder().decode(BenchFile.self, from: data) }

    public static func bundled() throws -> BenchFile { try parse(BoarData.data(.benchV01)) }

    public var queries: [EvalQuery] {
        items.map {
            EvalQuery(id: $0.id, category: $0.category, query: $0.question, setVersion: setVersion, grading: $0.grading,
                      danger: $0.danger, referenceTitles: $0.referenceTitles)
        }
    }
}

/// A question set the Benchmark screen offers.
public struct EvalQuestionSet: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        /// 12 bench v0.1 items, every one checked on the phone.
        case quick
        /// All 60 public bench v0.1 items.
        case bench
        /// The app's original 17 questions (set "1"), kept for Android parity and device requests.
        case smoke
    }

    public var kind: Kind
    public var queries: [EvalQuery]
    public var id: String { kind.rawValue }
    /// The version recorded on every row ("bench-v0.1" or "1").
    public var setVersion: String { queries.first?.setVersion ?? "" }
    /// How many questions the phone can check itself.
    public var checkedOnDevice: Int { queries.count { $0.grading?.checkedOnDevice ?? false } }

    public init(kind: Kind, queries: [EvalQuery]) { self.kind = kind; self.queries = queries }

    /// Quick check, Research bench v0.1 and the App smoke set, in that order; a set whose file is missing is left out.
    public static func bundled() -> [EvalQuestionSet] {
        var out: [EvalQuestionSet] = []
        if let bench = try? BenchFile.bundled() {
            let all = bench.queries
            let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            out.append(EvalQuestionSet(kind: .quick, queries: bench.quick.compactMap { byId[$0] }))
            out.append(EvalQuestionSet(kind: .bench, queries: all))
        }
        if let legacy = try? EvalSets.bundled() {
            out.append(EvalQuestionSet(kind: .smoke, queries: legacy.evalSet))
        }
        return out
    }
}

/// What the phone can grade on one answer, offline and without a model (docs/BENCHMARK-SCREEN.md D4–D6).
public enum BenchCheck {
    public struct Outcome: Sendable, Equatable {
        /// nil when the item is not a precheck item (no grading, venue list, first aid, judge-only) or the answer was cancelled.
        public var check: Precheck.Result?
        /// nil when the item names no reference article.
        public var sourceHit: Bool?
    }

    public static func evaluate(_ q: EvalQuery, answer: String, cancelled: Bool, retrievedTitles: [String]) -> Outcome {
        var check: Precheck.Result?
        if let g = q.grading, g.checkedOnDevice, !cancelled {
            check = Precheck.grade(question: q.query, grading: g, answer: answer)
        }
        // The app's own set names its expected articles instead of reference sources.
        let reference = q.referenceTitles.isEmpty ? q.expectedKbTitles : q.referenceTitles
        return Outcome(check: check, sourceHit: sourceHit(reference: reference, retrieved: retrievedTitles))
    }

    /// Whether retrieval kept one of the item's reference articles (titles compared case- and diacritic-insensitively).
    public static func sourceHit(reference: [String], retrieved: [String]) -> Bool? {
        if reference.isEmpty { return nil }
        func key(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces) }
        let wanted = Set(reference.map(key))
        return retrieved.contains { wanted.contains(key($0)) }
    }

    /// The row fields a check adds (`check`, `checkWhy`, `sourceHit`, plus the item's bench metadata).
    public static func rowFields(_ q: EvalQuery, _ o: Outcome) -> [(String, JSONValue?)] {
        [
            ("benchSet", .string(q.setVersion)), ("gradingType", q.grading.map { .string($0.type) }), ("danger", .bool(q.danger)),
            ("referenceTitles", JSONValue(strings: q.referenceTitles)),
            ("check", o.check.map { .string($0.status.rawValue) }), ("checkWhy", o.check.map { .string($0.why) }),
            ("checkPassed", o.check.map { .bool($0.passed) }), ("sourceHit", o.sourceHit.map(JSONValue.bool)),
        ]
    }
}
