import Foundation

/// The task a query asks for (src/routing/types.ts TaskType); the raw value is the TypeScript string.
public enum TaskType: String, Sendable, CaseIterable, Hashable {
    case greeting
    /// Talk to or about the assistant, and small requests no document can answer: no retrieval, length not capped.
    case conversation
    case chat
    case lookup
    case research
    case summarize
    case compare
    case calculate
    case extract
    case translate
    case code
    case unknown

    public var value: String { rawValue }

    public static func of(_ value: String) -> TaskType? { TaskType(rawValue: value) }
}

/// Deterministic, rule-based task classification (port of src/routing/classify.ts), explicitly NOT an LLM call.
/// Heuristic keyword/shape matching, but deterministic and testable: the same input always gives the same plan.
public enum Classify {
    private static let patterns: [(TaskType, JsRegex)] = {
        let raw: [(TaskType, String)] = [
        (.compare, #"\b(compare|versus|vs\.?|difference between|which is better)\b"#),
        // Portuguese ("Por que existem as estações do ano?" was "chat"). \b doesn't see accented letters: unaccented stems.
        (.compare, #"\bdiferen[çc]a entre\b|\bcompar(e|ar|a[çc][ãa]o)\b|\bqual [ée] melhor\b"#),
        (.summarize, #"\b(summarize|summarise|summary of|tl;?dr)\b"#),
        (.translate, #"\btranslate\b"#),
        (.code, #"```|\b(write (a |some )?code|debug this|refactor|fix this function|regex for)\b"#),
        (.calculate, #"\b(calculate|compute|how much is)\b|\d+\s*[+\-*/×÷]\s*\d"#),
        (.extract, #"\b(extract|list all|pull out|find every)\b"#),
        // Explanation/reasoning questions: never a one-sentence lookup, even when short and opening with "what".
        (.research, #"^(why|how)\b|\b(explain|caused?|causes|effects? of|impacts?|relate[sd]?|relationship|contrast|implications?)\b"#),
        (.research, #"^(por ?qu[eê]|como)\s|\b(explique|explica|explicar|causou|causas?|efeitos? d[eao]s?|impactos?)\b"#),
    ]
        return raw.map { ($0.0, JsRegex($0.1, flags: "i")) }
    }()

    // ONE greeting phrase, trailing punctuation only; anchored per segment (see isGreeting), not per query.
    private static let greetingPhrase = JsRegex(
        #"^(hi|hello|hey|hey there|yo|sup|wake up|good (morning|afternoon|evening|night)|how(?:'s| is| are) it going|how are you|what'?s up|thanks?( you)?|thank you|bye|goodbye|see ya|see you|ok(ay)?|cool|nice)[!.?~]*$"#,
        flags: "i"
    )
    private static let segmentSplit = JsRegex(#"[,;]|\band\b"#, flags: "i")

    /// Every comma/semicolon/"and" segment is a greeting phrase ("hey, what's up?"); "hi, can you compare X" is not.
    private static func isGreeting(_ trimmed: String) -> Bool {
        let segments = segmentSplit.split(trimmed).map(JsString.trim).filter { !$0.isEmpty }
        return !segments.isEmpty && segments.allSatisfy { greetingPhrase.containsMatch(in: $0) }
    }

    /// Questions to or about the assistant and chit-chat, where the knowledge base only adds noise ("whats your name?"
    /// retrieved Name). Anchored on the whole message, so "what is the name of the capital of Australia" still retrieves.
    private static let conversation = JsRegex(
        #"^(?:what'?s?\s+(?:is\s+)?your\s+name|who\s+are\s+you|what\s+are\s+you|what\s+can\s+you\s+do|(?:how\s+)?can\s+you\s+help(?:\s+me)?|who\s+(?:made|built|created|trained)\s+you|are\s+you\s+(?:an?\s+)?(?:ai|bot|robot|human|real|person|chatgpt|online|offline)|how\s+do\s+you\s+work|(?:tell\s+me\s+)?(?:a\s+)?joke|what\s+time\s+is\s+it|what'?s?\s+(?:is\s+)?the\s+time|what\s+day\s+is\s+(?:it|today)|what'?s?\s+(?:is\s+)?today'?s\s+date)(?:\s+(?:please|again|now|today))?[\s!.?~]*$"#,
        flags: "i"
    )

    private static let yesNo = JsRegex(
        #"^(is|are|was|were|do|does|did|can|could|should|will|would|has|have|é|e|são|sao|era|foi|posso|pode|podem|devo|deve|precisa|preciso|tem|há|ha|existe|vale)(?![\p{L}])[^?]*\?\s*$"#,
        flags: "iu"
    )
    private static let whStart = JsRegex(#"^(who|what|when|where|which|quem|o que|qual|quais|quando|onde|quantos?|quantas?)\s"#, flags: "i")
    private static let researchWords = JsRegex(#"\b(research|analyze|analyse|investigate|explore|explain in depth)\b"#, flags: "i")
    private static let wsRun = JsRegex(#"\s+"#)

    public static func classifyTask(_ query: String) -> TaskType {
        let trimmed = JsString.trim(query)
        if trimmed.isEmpty { return .unknown }
        if isGreeting(trimmed) { return .greeting }
        if conversation.containsMatch(in: trimmed) { return .conversation }
        for (type, re) in patterns where re.containsMatch(in: trimmed) { return type }
        let wordCount = wsRun.split(trimmed).count
        if whStart.containsMatch(in: trimmed + " ") && wordCount <= 12 { return .lookup }
        if wordCount > 25 || researchWords.containsMatch(in: trimmed) { return .research }
        // A yes/no question is a question about the world ("Is tipping expected in restaurants in Portugal?"): as a
        // lookup it declines when the library has nothing on topic, instead of a from-memory answer with no source.
        if yesNo.containsMatch(in: trimmed) { return .lookup }
        return .chat
    }

    /// Whether knowledge-base retrieval is irrelevant for this task type: a translation, calculation, code request,
    /// greeting or conversation doesn't get better from unrelated chunks; every other type (including "chat") retrieves.
    public static func isRetrievalIrrelevant(_ taskType: TaskType) -> Bool {
        taskType == .calculate || taskType == .translate || taskType == .code || taskType == .greeting || taskType == .conversation
    }
}
