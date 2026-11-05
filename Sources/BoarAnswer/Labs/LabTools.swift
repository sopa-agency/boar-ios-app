import BoarRAG
import BoarRouting

/// The Boar Labs answer plugins' decisions, pure (android `routing/LabTools.kt`): the order the tool slot tries them in,
/// when the check slot runs, and the dispatch both slots share. Each plugin's own question test (calculator, distance,
/// facts, CO hazard, guard) joins this as it is ported; LabToolsCombinationTests runs them together.
///
/// Lives in BoarAnswer, not BoarRouting as on Android: Boar Guard reads `AnswerText`, which is here.
public enum LabTools {
    /// `tool`: the receipt code ("calculator-battery", "facts-population", "verdict-guard-date"); `text`: the answer.
    public struct Hit: Sendable, Equatable {
        public let tool: String
        public let text: String
        public init(tool: String, text: String) { self.tool = tool; self.text = text }
    }

    /// Longer than any calculation, trip or fact question: a pasted text goes to the model and the instant tools don't
    /// scan it. Boar Cohazard reads any length: it is the safety answer and about ten times cheaper.
    public static let maxQuestion = 2_000

    /// Boar Calculator: CalcShortcut, with its own NumGuard lexicon over this and the earlier user turns.
    public static func calc(_ query: String, userTurns: [String]) -> Hit? {
        if query.utf16.count > maxQuestion { return nil }
        return CalcShortcut.answer(query, userTurns: userTurns).map { Hit(tool: $0.code, text: $0.text) }
    }

    private static func notEnglish(_ q: String) -> Bool { QueryContext.isPortugueseQuestion(q) || QueryContext.isSpanishQuestion(q) }

    /// A seed phrase or private key anywhere in the question: an instant fact or distance would drop that half of it.
    private static func seed(_ q: String) -> Bool { QueryContext.isSeedPhraseQuestion(q) }

    /// Boar Distance: English only, not a seed phrase; NumGuard's health lexicon over this and the earlier user turns
    /// keeps it off health.
    public static func distance(_ table: TravelDistance?, _ query: String, userTurns: [String]) -> Hit? {
        if query.utf16.count > maxQuestion || notEnglish(query) || seed(query) || ([query] + userTurns).contains(where: NumGuard.healthLexicon) {
            return nil
        }
        return table?.answer(query).map { Hit(tool: "calculator-travel-distance", text: $0.text) }
    }

    /// Boar Facts: English only, not a seed phrase; QueryContext's health detector over this and the earlier user turns
    /// keeps it off health.
    public static func facts(_ table: Facts?, _ query: String, userTurns: [String]) -> Hit? {
        if query.utf16.count > maxQuestion || notEnglish(query) || seed(query) || ([query] + userTurns).contains(where: QueryContext.isHealthQuestion) {
            return nil
        }
        return table?.answer(query).map { Hit(tool: "facts-\($0.template)", text: $0.text) }
    }

    /// Safety answers before the rest: Boar Cohazard's CO answer must win over a calculation or a fact in the same
    /// question ("How long can I run a propane heater in the camper at 0.5 kg per hour?"). Then Boar Polyglot: a question
    /// BOAR can't read gets its reply before a tool half-reads it. Grid order within a rank.
    public static func slotRank(_ labId: String) -> Int {
        switch labId {
        case "cohazard": 0
        case "polyglot": 1
        default: 2
        }
    }

    /// The first item with an answer; one that throws is skipped. Both slots dispatch through this.
    public static func first<T, R>(_ items: [T], _ run: (T) throws -> R?) -> R? {
        for item in items {
            if let r = try? run(item) { return r }
        }
        return nil
    }

    /// The check slot reads only a model's finished answer: not an instant tool answer, a stopped, timed-out or failed
    /// one, an empty one, or one written by Deep Research or a recap (`path` other than nil or "adaptive").
    public static func checksAnswer(instant: Bool, stopped: Bool, timedOut: Bool, failed: Bool, path: String?, blank: Bool) -> Bool {
        !instant && !stopped && !timedOut && !failed && (path == nil || path == "adaptive") && !blank
    }
}
