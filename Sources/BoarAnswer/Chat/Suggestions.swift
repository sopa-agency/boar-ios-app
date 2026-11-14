import BoarModels
import Foundation

/// The empty chat's suggested questions (port of src/ui-android/chat/suggestions.ts): only those a model answered correctly
/// and safely in that language, and whose source is installed. Data from `suggestions.json`.
public struct Suggestions: Codable, Sendable, Equatable {
    public struct Validation: Codable, Sendable, Equatable {
        public var version: Int
        /// model id → language → question keys.
        public var byModel: [String: [String: [String]]]
    }

    public struct Source: Codable, Sendable, Equatable {
        public var key: String
        public var corpus: [String]
        public var expect: [String]
        public var langs: [String]
    }

    public var validation: Validation
    public var sources: [Source]
    public var minSuggestions: Int

    /// coveredSuggestions: keys whose on-topic source is installed ("builtin" always) and was found in that language.
    public func covered(_ keys: [String], installed: some Collection<String>, lang: String) -> [String] {
        let have = Set(["builtin"]).union(installed)
        let byKey = Dictionary(sources.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        return keys.filter { k in
            guard let s = byKey[k] else { return false }
            return s.langs.contains(lang) && s.corpus.contains(where: have.contains)
        }
    }

    /// suggestionsFor: validated for the model and language ("pt…" is Portuguese, else English), and covered.
    public func forModel(_ modelId: String?, language: String?, installed: some Collection<String> = [String]()) -> [String] {
        guard let modelId, let byLang = validation.byModel[modelId] else { return [] }
        let lang = language?.hasPrefix("pt") == true ? "pt" : "en"
        return covered(byLang[lang] ?? [], installed: installed, lang: lang)
    }

    /// Prompt ideas shown in an empty chat, drawn again for each new chat (android ChatViewModel.IDEAS_SHOWN).
    public static let ideasShown = 3

    /// Short questions (two lines at most) from the evaluations: b1…b9 from BOAR's 17-question set (eval-set.json),
    /// b10…b21 from the public BOAR Bench v0.1 items, without its trap, emergency, crypto and restaurant questions
    /// (android ChatViewModel.BENCH_IDEAS).
    public static let benchIdeas = (1...21).map { "b\($0)" }

    /// Every prompt idea this model and language can show; a new chat draws a few at random (android refreshModel's
    /// ideaPool). Fewer than 3 tested on this model (a Hugging Face model has none; Qwen2.5 1.5B has 1 in Portuguese):
    /// filled from the ideas tested on the other models, same language, only for packs installed. Then the bench ideas.
    public func ideaPool(_ modelId: String?, language: String?, installed: some Collection<String> = [String]()) -> [String] {
        let own = forModel(modelId, language: language, installed: installed)
        let tested = own.count >= 3 ? own
            : own + validation.byModel.keys.sorted().flatMap { forModel($0, language: language, installed: installed) }
        var seen = Set<String>()
        return (tested + Self.benchIdeas).filter { seen.insert($0).inserted }
    }

    /// Fewer than this: the empty chat suggests adding a knowledge pack.
    public func showsKnowledgeHint(_ count: Int) -> Bool { count < minSuggestions }

    public static func parse(_ data: Data) throws -> Suggestions { try JSONDecoder().decode(Suggestions.self, from: data) }

    /// The `suggestions.json` bundled with BoarModels.
    public static func bundled() throws -> Suggestions { try parse(BoarData.data(.suggestions)) }
}
