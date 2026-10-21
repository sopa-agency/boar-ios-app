import Foundation

/// The model and corpus catalog, read from `catalog.json` (bundled in this module, copied from android-native's
/// `boar-data/`, which scripts/export-native-data.mjs writes from src/models/manifest.ts: one source of truth).
public struct Catalog: Codable, Sendable, Equatable {
    public var storageBudgetBytes: Int64
    public var ramBudgetBytes: Int64
    public var models: [CatalogAsset]
    public var tiers: [SetupTier]

    public init(storageBudgetBytes: Int64, ramBudgetBytes: Int64, models: [CatalogAsset], tiers: [SetupTier]) {
        self.storageBudgetBytes = storageBudgetBytes
        self.ramBudgetBytes = ramBudgetBytes
        self.models = models
        self.tiers = tiers
    }

    /// LLMs that can be the answer model at setup, the default tier first (manifest.ts ANSWER_MODELS).
    public var answerModels: [CatalogAsset] {
        Self.stableSorted(models.filter { $0.kind == .llm && $0.answerTier != nil }) { ($0.answerTier == .default ? 0 : 1) < ($1.answerTier == .default ? 0 : 1) }
    }

    /// Every suggested LLM the user can pick at setup, smallest first: the two answer tiers plus the other catalog models.
    public var setupModels: [CatalogAsset] {
        Self.stableSorted(models.filter { $0.kind == .llm && !$0.hidden }) { $0.sizeBytes < $1.sizeBytes }
    }

    public var defaultAnswerModel: CatalogAsset { answerModels.first { $0.answerTier == .default }! }
    public var compactAnswerModel: CatalogAsset { answerModels.first { $0.answerTier == .compact }! }
    public var requiredModels: [CatalogAsset] { models.filter(\.required) + [defaultAnswerModel] }
    public var corpusCatalog: [CatalogAsset] { models.filter { $0.kind == .corpus } }

    public func byId(_ id: String) -> CatalogAsset? { models.first { $0.id == id } }
    public func tier(_ id: String) -> SetupTier? { tiers.first { $0.id == id } }

    /// Kotlin `sortedBy` is stable; so is this.
    private static func stableSorted(_ a: [CatalogAsset], by less: (CatalogAsset, CatalogAsset) -> Bool) -> [CatalogAsset] {
        a.enumerated().sorted { l, r in
            if less(l.element, r.element) { return true }
            if less(r.element, l.element) { return false }
            return l.offset < r.offset
        }.map(\.element)
    }

    public static func parse(_ text: String) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(text.utf8))
    }

    public static func parse(data: Data) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// The catalog that ships with the app (`catalog.json` in this module's resources).
    public static func bundled() throws -> Catalog {
        try parse(data: BoarData.data(.catalog))
    }
}

public enum AssetKind: String, Codable, Sendable {
    case llm, embedding, corpus
}

public enum AnswerTier: String, Codable, Sendable {
    case `default`, compact
}

public struct CatalogAsset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: AssetKind
    public var label: String
    public var displayName: String?
    /// Path under the app's files directory once installed, e.g. "models/embedding.gguf".
    public var filename: String
    public var sizeBytes: Int64
    public var sha256: String
    public var sourceUrl: String
    public var license: String
    public var description: String
    public var required: Bool
    public var answerTier: AnswerTier?
    /// No longer suggested (manifest.ts `hidden`): listed only where it's already on the phone, and it keeps working there.
    public var hidden: Bool
    public var bundled: Bool
    public var format: String?
    public var requires: [String]
    /// Curated capabilities (manifest.ts); nil = not yet assessed, never an assumed capability set.
    public var capabilities: CatalogCapabilities?

    public init(
        id: String, kind: AssetKind, label: String, displayName: String? = nil, filename: String, sizeBytes: Int64, sha256: String,
        sourceUrl: String, license: String, description: String, required: Bool, answerTier: AnswerTier? = nil, hidden: Bool = false,
        bundled: Bool = false, format: String? = nil, requires: [String] = [], capabilities: CatalogCapabilities? = nil
    ) {
        self.id = id; self.kind = kind; self.label = label; self.displayName = displayName; self.filename = filename
        self.sizeBytes = sizeBytes; self.sha256 = sha256; self.sourceUrl = sourceUrl; self.license = license
        self.description = description; self.required = required; self.answerTier = answerTier; self.hidden = hidden
        self.bundled = bundled; self.format = format; self.requires = requires; self.capabilities = capabilities
    }

    /// Short UI name ("Qwen3 4B"), falling back to the technical label (manifest.ts displayNameOf).
    public var shortName: String { displayName ?? label }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, displayName, filename, sizeBytes, sha256, sourceUrl, license, description, required
        case answerTier, hidden, bundled, format, requires, capabilities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(AssetKind.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        filename = try c.decode(String.self, forKey: .filename)
        sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        sha256 = try c.decode(String.self, forKey: .sha256)
        sourceUrl = try c.decode(String.self, forKey: .sourceUrl)
        license = try c.decode(String.self, forKey: .license)
        description = try c.decode(String.self, forKey: .description)
        required = try c.decode(Bool.self, forKey: .required)
        answerTier = try c.decodeIfPresent(AnswerTier.self, forKey: .answerTier)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        bundled = try c.decodeIfPresent(Bool.self, forKey: .bundled) ?? false
        format = try c.decodeIfPresent(String.self, forKey: .format)
        requires = try c.decodeIfPresent([String].self, forKey: .requires) ?? []
        capabilities = try c.decodeIfPresent(CatalogCapabilities.self, forKey: .capabilities)
    }
}

/// What a model is good for (src/routing/types.ts ModelCapabilities): explicit, curated data, never inferred from the
/// filename. `roles` holds ModelRole strings ("fast", "general", ...); empty = not yet assessed, not "no roles".
///
/// Named `CatalogCapabilities` here (Kotlin: `ModelCapabilities`) because `BoarCore.ModelCapabilities` is the runtime
/// capability set of a loaded model session.
public struct CatalogCapabilities: Codable, Sendable, Equatable {
    public var roles: [String]
    public var supportsStructuredOutput: Bool?
    public var supportsLongContext: Bool?
    public var supportsToolLikeTasks: Bool?
    /// True only for models confirmed to need (and embed) a chat template; absent = the plain prompt shape.
    public var usesChatTemplate: Bool?
    /// Rough working-set estimate, same basis as the engine's pre-flight RAM check.
    public var estimatedMemoryMb: Double?
    /// Only from real telemetry or a benchmark, never invented.
    public var estimatedTokensPerSecond: Double?

    public init(
        roles: [String] = [], supportsStructuredOutput: Bool? = nil, supportsLongContext: Bool? = nil, supportsToolLikeTasks: Bool? = nil,
        usesChatTemplate: Bool? = nil, estimatedMemoryMb: Double? = nil, estimatedTokensPerSecond: Double? = nil
    ) {
        self.roles = roles; self.supportsStructuredOutput = supportsStructuredOutput; self.supportsLongContext = supportsLongContext
        self.supportsToolLikeTasks = supportsToolLikeTasks; self.usesChatTemplate = usesChatTemplate
        self.estimatedMemoryMb = estimatedMemoryMb; self.estimatedTokensPerSecond = estimatedTokensPerSecond
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roles = try c.decodeIfPresent([String].self, forKey: .roles) ?? []
        supportsStructuredOutput = try c.decodeIfPresent(Bool.self, forKey: .supportsStructuredOutput)
        supportsLongContext = try c.decodeIfPresent(Bool.self, forKey: .supportsLongContext)
        supportsToolLikeTasks = try c.decodeIfPresent(Bool.self, forKey: .supportsToolLikeTasks)
        usesChatTemplate = try c.decodeIfPresent(Bool.self, forKey: .usesChatTemplate)
        estimatedMemoryMb = try c.decodeIfPresent(Double.self, forKey: .estimatedMemoryMb)
        estimatedTokensPerSecond = try c.decodeIfPresent(Double.self, forKey: .estimatedTokensPerSecond)
    }
}

public struct SetupTier: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var description: String
    public var corpusPackIds: [String]

    public init(id: String, label: String, description: String, corpusPackIds: [String]) {
        self.id = id; self.label = label; self.description = description; self.corpusPackIds = corpusPackIds
    }
}

/// The `boar-data/*.json` files bundled with this module (copied from android-native's assets). Other modules that need
/// `personalities.json`, `suggestions.json`, `eval-set.json` or `bench-v0.1.json` read them from here.
public enum BoarData {
    public enum File: String, Sendable, CaseIterable {
        case catalog, personalities, suggestions
        case evalSet = "eval-set"
        /// The public boar-eval bench v0.1 (scripts/build-bench.py).
        case benchV01 = "bench-v0.1"
    }

    public struct MissingResource: Error, CustomStringConvertible, Sendable {
        public let name: String
        public var description: String { "bundled resource \(name).json is missing" }
    }

    public static func url(_ file: File) throws -> URL {
        guard let u = Bundle.module.url(forResource: file.rawValue, withExtension: "json") else { throw MissingResource(name: file.rawValue) }
        return u
    }

    public static func data(_ file: File) throws -> Data { try Data(contentsOf: url(file)) }
}
