import Foundation

/// A conceptual role in a routing plan, not a specific model (src/routing/types.ts ModelRole). Only one generation
/// context is resident at a time, so a plan using several roles runs them one after another, paying a real model
/// switch each time. The raw value is the TypeScript string.
public enum ModelRole: String, Sendable, CaseIterable, Hashable {
    case fast, general, reasoning, verifier, embedding

    public var value: String { rawValue }

    /// Kotlin `of`: the role for a TypeScript string, nil when unknown (Kotlin throws).
    public static func of(_ value: String) -> ModelRole? { ModelRole(rawValue: value) }
}

/// A named routing configuration the user picks (settings.ts routingPreset; "balanced" when unset).
public enum RoutingPreset: String, Sendable, CaseIterable, Hashable {
    case simple, balanced, research, custom

    public var value: String { rawValue }

    /// settings.ts getRoutingPreset's default.
    public static let `default` = RoutingPreset.balanced

    public static func of(_ value: String) -> RoutingPreset? { RoutingPreset(rawValue: value) }
}

/// One stage in an execution plan.
public enum RoutingStepType: String, Sendable, CaseIterable, Hashable {
    case classify, retrieve, generate, verify, synthesize

    public var value: String { rawValue }

    public static func of(_ value: String) -> RoutingStepType? { RoutingStepType(rawValue: value) }
}
