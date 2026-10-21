import Foundation

/// Rough RAM-fit estimate for a GGUF model on this device (port of src/models/compatibility.ts), shared by the catalog
/// UI and the routing profiles. Heuristic, not a measurement: a quantized model's resident working set tracks its file
/// size plus context/KV overhead, approximated as 1.15x. (BoarModels may carry its own copy of the same rule.)
public enum ModelCompatibility: String, Sendable, Equatable {
    case green, yellow, red, unknown

    public var value: String { rawValue }

    public static func compute(sizeBytes: Int64, deviceRamBytes: Int64) -> ModelCompatibility {
        if deviceRamBytes <= 0 { return .unknown }
        let estimatedRamBytes = Double(sizeBytes) * 1.15
        if estimatedRamBytes <= Double(deviceRamBytes) * 0.65 { return .green }
        if estimatedRamBytes <= Double(deviceRamBytes) * 0.9 { return .yellow }
        return .red
    }
}

/// What routing needs to know about one installable model: the catalog fields of Kotlin's `CatalogAsset` that
/// Profiles reads. BoarModels' catalog asset is mapped onto this by the caller (the routing target does not depend
/// on BoarModels).
public struct RoutableModel: Sendable, Equatable {
    public var id: String
    /// `kind == AssetKind.LLM`: only language models take part in routing.
    public var isLanguageModel: Bool
    public var sizeBytes: Int64
    /// `capabilities?.roles` (ModelRole strings); nil = capabilities not yet assessed.
    public var roles: [String]?
    public var estimatedMemoryMb: Double?
    public var estimatedTokensPerSecond: Double?

    public init(
        id: String, isLanguageModel: Bool = true, sizeBytes: Int64, roles: [String]? = nil,
        estimatedMemoryMb: Double? = nil, estimatedTokensPerSecond: Double? = nil
    ) {
        self.id = id
        self.isLanguageModel = isLanguageModel
        self.sizeBytes = sizeBytes
        self.roles = roles
        self.estimatedMemoryMb = estimatedMemoryMb
        self.estimatedTokensPerSecond = estimatedTokensPerSecond
    }
}

/// Model profiles and presets (port of src/routing/profiles.ts): given what is actually downloaded, which model fills
/// each role. Configuration only: it doesn't decide when to switch models, only what is available to switch to. Does
/// not require three models.
public enum Profiles {
    public struct ModelProfile: Sendable, Equatable {
        /// "" when the role could not be resolved (enabled = false).
        public var modelId: String
        public var role: ModelRole
        public var enabled: Bool
        /// True if this came from an explicit user role assignment, false if auto-resolved.
        public var userOverride: Bool
        public var estimatedMemoryMb: Double?
        public var estimatedTokensPerSecond: Double?
        public var compatibilityStatus: ModelCompatibility

        public init(
            modelId: String, role: ModelRole, enabled: Bool, userOverride: Bool,
            estimatedMemoryMb: Double? = nil, estimatedTokensPerSecond: Double? = nil, compatibilityStatus: ModelCompatibility
        ) {
            self.modelId = modelId
            self.role = role
            self.enabled = enabled
            self.userOverride = userOverride
            self.estimatedMemoryMb = estimatedMemoryMb
            self.estimatedTokensPerSecond = estimatedTokensPerSecond
            self.compatibilityStatus = compatibilityStatus
        }
    }

    public enum RoleNeed: Sendable { case required, optional }

    /// Which roles a preset uses, in declaration order (the order of the returned profiles), and whether each is
    /// required or optional. Simple is one model (today's single-pass chat); Custom has no fixed roles.
    public static let presetDefinitions: [RoutingPreset: [(role: ModelRole, need: RoleNeed)]] = [
        .simple: [(.general, .required)],
        .balanced: [(.general, .required), (.fast, .optional), (.embedding, .optional)],
        .research: [(.reasoning, .required), (.general, .optional), (.verifier, .optional), (.embedding, .optional)],
        .custom: [],
    ]

    /// A model is available for routing once it is on disk, not just in the catalog.
    public struct AvailableModel: Sendable, Equatable {
        public var model: RoutableModel
        public var present: Bool
        public init(_ model: RoutableModel, present: Bool) {
            self.model = model
            self.present = present
        }
        public init(model: RoutableModel, present: Bool) {
            self.model = model
            self.present = present
        }
    }

    /// Resolves a role to a downloaded model: 1. the user's override for the role, if present on disk; 2. the first
    /// present model whose curated capabilities list the role; 3. the active/default model ([fallbackModelId]) if
    /// present (flagged: its capabilities don't list the role); 4. an explicit disabled profile. Never throws and never
    /// routes to a model that isn't on disk. Empty ids count as unset, as in JavaScript.
    public static func resolveModelForRole(
        _ role: ModelRole,
        available: [AvailableModel],
        overrides: [ModelRole: String],
        deviceRamBytes: Int64,
        fallbackModelId: String? = nil
    ) -> ModelProfile {
        let presentModels = available.filter(\.present).map(\.model)
        // new Map(entries): the last entry with a given id wins.
        var presentById: [String: RoutableModel] = [:]
        for m in presentModels { presentById[m.id] = m }

        if let overrideId = overrides[role], !overrideId.isEmpty, let m = presentById[overrideId] {
            return toProfile(m, role, userOverride: true, deviceRamBytes)
        }

        if let curated = presentModels.first(where: { $0.roles?.contains(role.value) == true }) {
            return toProfile(curated, role, userOverride: false, deviceRamBytes)
        }

        if let fallback = fallbackModelId, !fallback.isEmpty, let m = presentById[fallback] {
            return toProfile(m, role, userOverride: false, deviceRamBytes)
        }

        return ModelProfile(modelId: "", role: role, enabled: false, userOverride: false, compatibilityStatus: .unknown)
    }

    private static func toProfile(_ model: RoutableModel, _ role: ModelRole, userOverride: Bool, _ deviceRamBytes: Int64) -> ModelProfile {
        ModelProfile(
            modelId: model.id,
            role: role,
            enabled: true,
            userOverride: userOverride,
            estimatedMemoryMb: model.estimatedMemoryMb ?? JsNumber.round((Double(model.sizeBytes) * 1.15) / Double(1024 * 1024)),
            estimatedTokensPerSecond: model.estimatedTokensPerSecond,
            compatibilityStatus: ModelCompatibility.compute(sizeBytes: model.sizeBytes, deviceRamBytes: deviceRamBytes)
        )
    }

    /// Every role the preset uses, resolved. Roles that can't be resolved are still returned (enabled = false), so the
    /// caller can show why the preset isn't fully functional instead of silently missing a step.
    public static func buildModelProfiles(
        _ preset: RoutingPreset,
        available: [AvailableModel],
        overrides: [ModelRole: String],
        deviceRamBytes: Int64,
        fallbackModelId: String? = nil
    ) -> [ModelProfile] {
        presetDefinitions[preset, default: []].map {
            resolveModelForRole($0.role, available: available, overrides: overrides, deviceRamBytes: deviceRamBytes, fallbackModelId: fallbackModelId)
        }
    }
}
