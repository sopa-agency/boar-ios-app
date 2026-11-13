import BoarAnswer
import BoarCore
import BoarModels
import BoarRAG
import Foundation

/// A source as the chat shows it (and stores with the answer): the passage the model read, and its similarity to the question.
struct ChatSource: Hashable, Sendable, Identifiable {
    var number: Int
    var title: String
    var source: String?
    var relevance: Double?
    var similarity: Double?
    var docId: String?
    var body: String
    var id: Int { number }

    init(number: Int, chunk: Chunk) {
        self.number = number
        title = chunk.title
        source = chunk.source
        relevance = chunk.relevance
        similarity = chunk.similarity
        docId = chunk.docId
        body = chunk.body
    }

    init(number: Int, title: String, source: String?, relevance: Double?, similarity: Double?, docId: String?, body: String) {
        self.number = number; self.title = title; self.source = source; self.relevance = relevance
        self.similarity = similarity; self.docId = docId; self.body = body
    }

    /// A link to the article when the source is a URL (packs keep the Wikipedia address).
    var url: URL? {
        guard let source, source.hasPrefix("http://") || source.hasPrefix("https://") else { return nil }
        return URL(string: source)
    }
}

/// The measured facts of one answer (android `Receipt`), kept in the message's meta so a reopened chat still shows it.
struct Receipt: Hashable, Sendable {
    /// From the question being sent to the last token.
    var totalMs: Double
    /// From the question being sent to the first token: search, model load, reading the sources and the prompt.
    var ttftMs: Double
    var tokPerSec: Double
    var tokens: Int
    var model: String?
    var retrievalMs: Double?
    var prefillMs: Double?
    var contextTokens: Int?
    /// iOS addition: the model load this answer waited for (nil when it was resident).
    var loadMs: Double?
    /// Why the answer came in Succinct though Detailed was picked: "health" or "seed" (ShortAnswer), shown under it.
    var styleNote: String?
    /// The Boar Labs tool that answered instead of the model and/or the check that repaired it ("calculator-battery",
    /// "facts-population+verdict-guard-date"); nil when the model wrote it as is.
    var tool: String?
    /// How it was answered: nil (the normal answer), "deep" (Deep Research), "chat" (written from this chat), "adaptive".
    var path: String?

    var json: JSONValue {
        var o: [String: JSONValue] = ["totalMs": .double(totalMs), "ttftMs": .double(ttftMs), "tokPerSec": .double(tokPerSec), "tokens": JSONValue(tokens)]
        if let model { o["model"] = .string(model) }
        if let retrievalMs { o["retrievalMs"] = .double(retrievalMs) }
        if let prefillMs { o["prefillMs"] = .double(prefillMs) }
        if let contextTokens { o["contextTokens"] = JSONValue(contextTokens) }
        if let loadMs { o["loadMs"] = .double(loadMs) }
        if let styleNote { o["styleNote"] = .string(styleNote) }
        if let tool { o["tool"] = .string(tool) }
        if let path { o["path"] = .string(path) }
        return .object(o)
    }

    init(totalMs: Double, ttftMs: Double, tokPerSec: Double, tokens: Int, model: String?, retrievalMs: Double?, prefillMs: Double?, contextTokens: Int?, loadMs: Double?,
         styleNote: String? = nil, tool: String? = nil, path: String? = nil) {
        self.totalMs = totalMs; self.ttftMs = ttftMs; self.tokPerSec = tokPerSec; self.tokens = tokens; self.model = model
        self.retrievalMs = retrievalMs; self.prefillMs = prefillMs; self.contextTokens = contextTokens; self.loadMs = loadMs
        self.styleNote = styleNote
        self.tool = tool
        self.path = path
    }

    init?(json o: JSONValue) {
        guard let total = o["totalMs"]?.doubleValue, let ttft = o["ttftMs"]?.doubleValue, let rate = o["tokPerSec"]?.doubleValue,
              let tokens = o["tokens"]?.doubleValue else { return nil }
        self.init(totalMs: total, ttftMs: ttft, tokPerSec: rate, tokens: Int(tokens), model: o["model"]?.stringValue,
                  retrievalMs: o["retrievalMs"]?.doubleValue, prefillMs: o["prefillMs"]?.doubleValue,
                  contextTokens: o["contextTokens"]?.doubleValue.map { Int($0) }, loadMs: o["loadMs"]?.doubleValue,
                  styleNote: o["styleNote"]?.stringValue, tool: o["tool"]?.stringValue, path: o["path"]?.stringValue)
    }

    /// "9.1 s" under a minute, "2 min 5 s" above (ReceiptFormat.seconds).
    static func seconds(_ ms: Double) -> String {
        if ms < 60_000 { return String(format: "%.1f s", ms / 1000) }
        let s = Int((ms / 1000).rounded())
        return "\(s / 60) min \(s % 60) s"
    }

    static func rate(_ tokPerSec: Double) -> String { String(format: "%.1f", tokPerSec) }

    /// About 0.75 English words per token.
    static func words(_ tokens: Double) -> Int { Int((tokens * 0.75).rounded()) }
}

/// One chat bubble.
struct ChatItem: Identifiable, Hashable, Sendable {
    var id: String
    var role: String
    var text: String
    var sources: [ChatSource] = []
    var feedback: String?
    var stopped = false
    var timedOut = false
    var receipt: Receipt?
    /// The steps the answer actually went through, in order (live answers only; a reopened chat has none).
    var steps: [AnswerStep] = []
    /// How many sources the search found (nil when the answer didn't search).
    var sourceCount: Int?
    /// From the question being sent to the end of the answer.
    var answerSeconds: Double?
    /// How long the model reasoned before writing (thinking models only).
    var thinkingSeconds: Double?
    /// The answer failed: what to tell the user, shown inside the answer row with Try Again.
    var failure: String?
    /// The failure is "no answer model": the row offers Open Models instead of Try Again.
    var failureNoModel = false

    var isUser: Bool { role == "user" }
}

/// One step of an answer as the chat shows it, recorded when the pipeline reports it.
struct AnswerStep: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case loading, searching, thinking, splitting, subQuestion, writing
    }

    var kind: Kind
    var startedAt: Date
    /// Deep Research: the sub-question being researched (1-based) and how many there are.
    var index: Int?
    var count: Int?

    var symbol: AppIcon {
        switch kind {
        case .loading: Symbols.model
        case .searching: Symbols.search
        case .thinking: Symbols.thinking
        case .splitting, .subQuestion: "list.number"
        case .writing: "pencil.line"
        }
    }
}

/// What the assistant is doing for the message being answered.
enum ChatActivity: Hashable, Sendable {
    case loadingModel
    case retrieving
    case thinking
    case generating
    case researching(ResearchStage, index: Int?, count: Int?)

    var label: String {
        switch self {
        case .loadingModel: String(localized: "Loading the model…")
        case .retrieving: String(localized: "Searching your library…")
        case .thinking: String(localized: "Thinking…")
        case .generating: String(localized: "Writing…")
        case .researching(.decomposing, _, _): String(localized: "Splitting your question…")
        case .researching(.researching, let i, let n): String(localized: "Sub-question \(i ?? 1) of \(n ?? 1)")
        case .researching(.synthesizing, _, _): String(localized: "Writing…")
        }
    }

    /// The step this activity shows as (synthesizing the research is writing the answer).
    var stepKind: AnswerStep.Kind {
        switch self {
        case .loadingModel: .loading
        case .retrieving: .searching
        case .thinking: .thinking
        case .generating: .writing
        case .researching(.decomposing, _, _): .splitting
        case .researching(.researching, _, _): .subQuestion
        case .researching(.synthesizing, _, _): .writing
        }
    }
}

/// The meta JSON stored with an answer (same keys as android ChatViewModel.metaOf).
enum MessageMeta {
    static func encode(_ sources: [ChatSource], _ receipt: Receipt?) -> String {
        var o: [String: JSONValue] = [
            "sources": .array(sources.map { s in
                var e: [String: JSONValue] = ["title": .string(s.title), "body": .string(s.body)]
                if let v = s.source { e["source"] = .string(v) }
                if let v = s.relevance { e["relevance"] = .double(v) }
                if let v = s.similarity { e["similarity"] = .double(v) }
                if let v = s.docId { e["docId"] = .string(v) }
                return .object(e)
            }),
        ]
        if let receipt { o["receipt"] = receipt.json }
        return JSONValue.object(o).jsonString
    }

    static func sources(_ meta: String?) -> [ChatSource] {
        guard let meta, let root = JSONValue(jsonString: meta), let list = root["sources"]?.arrayValue else { return [] }
        return list.enumerated().compactMap { i, e in
            guard let title = e["title"]?.stringValue else { return nil }
            return ChatSource(number: i + 1, title: title, source: e["source"]?.stringValue, relevance: e["relevance"]?.doubleValue,
                              similarity: e["similarity"]?.doubleValue, docId: e["docId"]?.stringValue, body: e["body"]?.stringValue ?? "")
        }
    }

    static func receipt(_ meta: String?) -> Receipt? {
        guard let meta, let root = JSONValue(jsonString: meta), let r = root["receipt"] else { return nil }
        return Receipt(json: r)
    }
}

/// The prompt ideas of the empty chat by key: a topic and a research question (chat.suggestionTopics.* / chat.suggestions.*,
/// and native.chat.suggestions.b* for the bench ideas, in the Android strings).
enum PromptIdea {
    static func text(_ key: String) -> (topic: String, question: String)? {
        switch key {
        case "q1": (String(localized: "Science"), String(localized: "How Earth's tilt creates the seasons, and why they flip between hemispheres"))
        case "q2": (String(localized: "Health"), String(localized: "Pandemics and epidemics: how outbreaks spread and how they're classified"))
        case "q3": (String(localized: "Quick math"), String(localized: "What is 30 °C in Fahrenheit?"))
        case "q4": (String(localized: "First aid"), String(localized: "First aid for nosebleeds: what works and what to avoid"))
        case "q7": (String(localized: "Climate"), String(localized: "The greenhouse effect: which gases trap heat, and how"))
        case "q8": (String(localized: "Weather"), String(localized: "How monsoons form, and why they matter for farming in South Asia"))
        case "q9": (String(localized: "Earth science"), String(localized: "Plate tectonics: how moving plates build mountains and cause earthquakes"))
        case "b1": (String(localized: "History of science"), String(localized: "Darwin, Wallace and the discovery of natural selection"))
        case "b2": (String(localized: "Health"), String(localized: "How vaccines train the immune system, from smallpox to mRNA"))
        case "b3": (String(localized: "Biology"), String(localized: "Photosynthesis step by step: from sunlight to sugar"))
        case "b4": (String(localized: "History"), String(localized: "The French and Industrial Revolutions compared: causes and lasting effects"))
        case "b5": (String(localized: "History"), String(localized: "Why the Western Roman Empire fell: the main theories"))
        case "b6": (String(localized: "Space"), String(localized: "How black holes form, and what happens at the event horizon"))
        case "b7": (String(localized: "People"), String(localized: "Napoleon Bonaparte: his rise, his wars and his legacy in Europe"))
        case "b8": (String(localized: "Medicine"), String(localized: "Antibiotic resistance: why bacteria adapt, and what slows it"))
        case "b9": (String(localized: "Geography"), String(localized: "Canberra: why Australia built a new capital"))
        case "b10": (String(localized: "Myths"), String(localized: "The Great Wall of China: its history, its length and the Moon myth"))
        case "b11": (String(localized: "Animals"), String(localized: "Polar bears and grizzlies compared: size, diet and habitat"))
        case "b12": (String(localized: "Geography"), String(localized: "Brazil and Russia compared: population, area and economy"))
        case "b13": (String(localized: "Health"), String(localized: "How mosquitoes spread disease, and why HIV isn't one of them"))
        case "b14": (String(localized: "Health"), String(localized: "Exercise and health: how much adults need, and why"))
        case "b15": (String(localized: "Travel"), String(localized: "Kyoto's role in Japanese history and culture"))
        case "b16": (String(localized: "Earth science"), String(localized: "Mount Kilimanjaro: how a volcano became Africa's highest peak"))
        case "b17": (String(localized: "History"), String(localized: "The Berlin Wall: why it was built and how it fell"))
        case "b18": (String(localized: "Animals"), String(localized: "How cheetahs reach top speed, and how long they can keep it"))
        case "b19": (String(localized: "Travel"), String(localized: "Travelling in Brazil: plugs, voltage and emergency numbers"))
        case "b20": (String(localized: "Geography"), String(localized: "Japan and Germany compared: population density and an aging society"))
        case "b21": (String(localized: "Health"), String(localized: "Dengue fever: symptoms, how it spreads, and why a second infection is riskier"))
        default: nil
        }
    }
}

/// The catalog label without its parenthesis ("Qwen3-4B-Instruct-2507"), as the header shows it (shortModelLabel).
func shortModelLabel(_ label: String) -> String {
    let stripped = label.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    return stripped.isEmpty ? label.trimmingCharacters(in: .whitespaces) : stripped
}
