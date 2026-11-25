import BoarModels
import Foundation

/// A topic of bench questions (android engine/eval `BenchTopics.kt`, v2.0.0; adam, Nov 14: "make categories, so we can
/// test comparison, research, quick questions, calculators... a smaller generic one, another with the most problematic
/// questions"): one versioned file, `<id>.v<version>.json`, bundled with BoarModels (`Topics/`, copied byte for byte from
/// android's assets/boar-data/topics). t9 reviews each file before its numbers count (`status`).
///
/// A question either names one of the fixed set's (eval-set.json, `TopicQuestion.fromSet`) and runs it exactly as it is
/// there, or brings its own text. Its `TopicRules` say what the computer can check; `TopicQuestion.toRead` says what right
/// looks like for a person.
public struct BenchTopic: Codable, Sendable, Equatable {
    public var id: String
    public var version: Int
    /// "draft, for t9's review" until t9 signs it off.
    public var status: String
    public var title: String
    public var titlePt: String?
    public var about: String
    /// The Boar Labs plugins that answer and check while this topic runs; nil is the labs switched on in the app.
    public var labs: [String]?
    /// At the complete level its questions also run through Deep Research (adam, Nov 14: "complete ... and deep research").
    public var deepResearch: Bool
    public var questions: [TopicQuestion]

    public init(id: String, version: Int, status: String = "", title: String, titlePt: String? = nil, about: String = "",
                labs: [String]? = nil, deepResearch: Bool = false, questions: [TopicQuestion]) {
        self.id = id; self.version = version; self.status = status; self.title = title; self.titlePt = titlePt
        self.about = about; self.labs = labs; self.deepResearch = deepResearch; self.questions = questions
    }

    private enum CodingKeys: String, CodingKey { case id, version, status, title, titlePt, about, labs, deepResearch, questions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = try c.decode(Int.self, forKey: .version)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        title = try c.decode(String.self, forKey: .title)
        titlePt = try c.decodeIfPresent(String.self, forKey: .titlePt)
        about = try c.decodeIfPresent(String.self, forKey: .about) ?? ""
        labs = try c.decodeIfPresent([String].self, forKey: .labs)
        deepResearch = try c.decodeIfPresent(Bool.self, forKey: .deepResearch) ?? false
        questions = try c.decode([TopicQuestion].self, forKey: .questions)
    }

    /// The set version its own questions' rows carry: "plugins-v1".
    public var setVersion: String { "\(id)-v\(version)" }

    public struct BadTopic: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { message }
    }

    /// Its questions as the runner takes them; one from the fixed set is that question unchanged (ids, text, set version).
    public func queries(_ sets: EvalSets) throws -> [EvalQuery] {
        let fixed = Dictionary((sets.evalSet + sets.extraSets).map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        return try questions.map { q in
            if q.fromSet {
                guard let f = fixed[q.id] else { throw BadTopic(message: "topic \(id): \(q.id) is not in the fixed set") }
                return f
            }
            guard let text = q.query else { throw BadTopic(message: "topic \(id): \(q.id) has no query") }
            return EvalQuery(id: q.id, category: q.category ?? id, query: text, setVersion: setVersion)
        }
    }

    public func question(_ id: String) -> TopicQuestion? { questions.first { $0.id == id } }

    /// The title in the app's language.
    public func title(pt: Bool) -> String { pt ? titlePt ?? title : title }

    public static func parse(_ data: Data) throws -> BenchTopic { try JSONDecoder().decode(BenchTopic.self, from: data) }

    private static let fileNamePattern = try! NSRegularExpression(pattern: #"^([a-z][a-z0-9-]*)\.v(\d+)\.json$"#)

    /// "plugins.v1.json" -> ("plugins", 1); nil for any other name.
    public static func fileName(_ name: String) -> (id: String, version: Int)? {
        let ns = name as NSString
        guard let m = fileNamePattern.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)),
              let v = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return (ns.substring(with: m.range(at: 1)), v)
    }

    /// The newest version of each topic among `names`: the file names to read.
    public static func newest(_ names: [String]) -> [String] {
        var best: [String: (name: String, version: Int)] = [:]
        for n in names {
            guard let f = fileName(n) else { continue }
            if let b = best[f.id], b.version >= f.version { continue }
            best[f.id] = (n, f.version)
        }
        return best.values.map(\.name).sorted()
    }

    /// The bundled topic files, the newest version of each, by id (android DeviceEvalRunner.topics); a file that doesn't
    /// parse is left out.
    public static func bundled() -> [String: BenchTopic] {
        let files = BoarData.topicFiles()
        var out: [String: BenchTopic] = [:]
        for n in newest(Array(files.keys)) {
            if let d = files[n], let t = try? parse(d) { out[t.id] = t }
        }
        return out
    }
}

public struct TopicQuestion: Codable, Sendable, Equatable {
    public var id: String
    public var query: String?
    public var category: String?
    /// The fixed set's question with this id, as it is there.
    public var fromSet: Bool
    public var rules: TopicRules?
    /// What right looks like, for the person reading the answer.
    public var toRead: String
    /// Today fails this, and a fix is known (a board card or a brief): its failure shows as "known", apart from a
    /// regression (t9 1058: "a rule must say what right looks like, never what happens today").
    public var knownIssue: String?
    /// Asked only with this plugin on: skipped, and said so, when the run had it off.
    public var needsLab: String?

    public init(id: String, query: String? = nil, category: String? = nil, fromSet: Bool = false, rules: TopicRules? = nil,
                toRead: String = "", knownIssue: String? = nil, needsLab: String? = nil) {
        self.id = id; self.query = query; self.category = category; self.fromSet = fromSet; self.rules = rules
        self.toRead = toRead; self.knownIssue = knownIssue; self.needsLab = needsLab
    }

    private enum CodingKeys: String, CodingKey { case id, query, category, fromSet, rules, toRead, knownIssue, needsLab }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        query = try c.decodeIfPresent(String.self, forKey: .query)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        fromSet = try c.decodeIfPresent(Bool.self, forKey: .fromSet) ?? false
        rules = try c.decodeIfPresent(TopicRules.self, forKey: .rules)
        toRead = try c.decodeIfPresent(String.self, forKey: .toRead) ?? ""
        knownIssue = try c.decodeIfPresent(String.self, forKey: .knownIssue)
        needsLab = try c.decodeIfPresent(String.self, forKey: .needsLab)
    }
}

/// What the computer checks on one answer (adam, Nov 14: "we could have a score and topics. like, bad on this, good on
/// those"). Every rule set must hold for a pass; an answer with no rule is "to read".
public struct TopicRules: Codable, Sendable, Equatable {
    /// The plugin that must answer: its receipt code ("calculator-battery"), from the row's tool or reason codes.
    public var tool: String?
    /// No plugin answers it: the model does (a health question a calculator must leave alone).
    public var noTool = false
    /// The plugin's exact text.
    public var answerIs: String?
    public var answerStartsWith: String?
    /// Each must be in the answer (case ignored).
    public var answerHas: [String] = []
    /// At least one of these must be in the answer (spellings of one fact: "Canberra").
    public var answerHasAny: [String] = []
    /// One of each group must be in the answer: two facts, each in several wordings ("twice" / "double" / "2 times").
    public var answerHasEach: [[String]] = []
    public var answerHasNot: [String] = []
    /// "en" or "pt": the language the answer is clearly in (AnswerLanguage.clear).
    public var language: String?
    /// No [n] without a real source: every [n] is one of the sources the answer had.
    public var citesOnlyRealSources = false
    /// Sources whose titles must not be among the answer's (the bread that cited "Cutlet").
    public var sourcesNot: [String] = []
    /// None of the user's own files among the sources.
    public var noFileSources = false
    /// Numbers read right: each must appear in the answer, within its tolerance.
    public var numbers: [NumberRule] = []
    /// At least one of these: one fact in several units ("5,895 m" or "19,341 ft").
    public var numbersAny: [NumberRule] = []
    /// Known wrong numbers that must not appear.
    public var numbersNot: [NumberRule] = []
    /// The cards CardRules.find must find: "steps", "chart", "table", "facts", "compare".
    public var cards: [String] = []
    /// A chart card with at least this many points.
    public var minChartPoints: Int?
    /// Kept short: answered in Succinct whatever the run's style (ShortAnswer: health, seed phrases, small talk).
    public var keptShort = false

    public init(tool: String? = nil, noTool: Bool = false, answerIs: String? = nil, answerStartsWith: String? = nil, answerHas: [String] = [],
                answerHasAny: [String] = [], answerHasEach: [[String]] = [], answerHasNot: [String] = [], language: String? = nil,
                citesOnlyRealSources: Bool = false, sourcesNot: [String] = [], noFileSources: Bool = false, numbers: [NumberRule] = [],
                numbersAny: [NumberRule] = [], numbersNot: [NumberRule] = [], cards: [String] = [], minChartPoints: Int? = nil, keptShort: Bool = false) {
        self.tool = tool; self.noTool = noTool; self.answerIs = answerIs; self.answerStartsWith = answerStartsWith
        self.answerHas = answerHas; self.answerHasAny = answerHasAny; self.answerHasEach = answerHasEach; self.answerHasNot = answerHasNot
        self.language = language; self.citesOnlyRealSources = citesOnlyRealSources; self.sourcesNot = sourcesNot
        self.noFileSources = noFileSources; self.numbers = numbers; self.numbersAny = numbersAny; self.numbersNot = numbersNot
        self.cards = cards; self.minChartPoints = minChartPoints; self.keptShort = keptShort
    }

    private enum CodingKeys: String, CodingKey {
        case tool, noTool, answerIs, answerStartsWith, answerHas, answerHasAny, answerHasEach, answerHasNot, language, citesOnlyRealSources,
             sourcesNot, noFileSources, numbers, numbersAny, numbersNot, cards, minChartPoints, keptShort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        noTool = try c.decodeIfPresent(Bool.self, forKey: .noTool) ?? false
        answerIs = try c.decodeIfPresent(String.self, forKey: .answerIs)
        answerStartsWith = try c.decodeIfPresent(String.self, forKey: .answerStartsWith)
        answerHas = try c.decodeIfPresent([String].self, forKey: .answerHas) ?? []
        answerHasAny = try c.decodeIfPresent([String].self, forKey: .answerHasAny) ?? []
        answerHasEach = try c.decodeIfPresent([[String]].self, forKey: .answerHasEach) ?? []
        answerHasNot = try c.decodeIfPresent([String].self, forKey: .answerHasNot) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language)
        citesOnlyRealSources = try c.decodeIfPresent(Bool.self, forKey: .citesOnlyRealSources) ?? false
        sourcesNot = try c.decodeIfPresent([String].self, forKey: .sourcesNot) ?? []
        noFileSources = try c.decodeIfPresent(Bool.self, forKey: .noFileSources) ?? false
        numbers = try c.decodeIfPresent([NumberRule].self, forKey: .numbers) ?? []
        numbersAny = try c.decodeIfPresent([NumberRule].self, forKey: .numbersAny) ?? []
        numbersNot = try c.decodeIfPresent([NumberRule].self, forKey: .numbersNot) ?? []
        cards = try c.decodeIfPresent([String].self, forKey: .cards) ?? []
        minChartPoints = try c.decodeIfPresent(Int.self, forKey: .minChartPoints)
        keptShort = try c.decodeIfPresent(Bool.self, forKey: .keptShort) ?? false
    }

    public var isEmpty: Bool { self == TopicRules() }
}

/// A number and how far off it may be, as a share of it (0.01 is 1 %).
public struct NumberRule: Codable, Sendable, Equatable {
    public var value: Double
    public var tolerance: Double
    public var label: String

    public init(_ value: Double, tolerance: Double = 0.01, label: String = "") { self.value = value; self.tolerance = tolerance; self.label = label }

    private enum CodingKeys: String, CodingKey { case value, tolerance, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(Double.self, forKey: .value)
        tolerance = try c.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.01
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}
