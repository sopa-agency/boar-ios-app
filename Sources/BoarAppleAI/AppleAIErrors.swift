import BoarCore
import Foundation
import FoundationModels

// MARK: - Availability

/// Whether Apple's on-device model can run, in terms the UI can show (Settings → Model, setup sheet).
public enum AppleModelAvailability: Sendable, Equatable, Hashable {
    case available
    /// The hardware can't run Apple Intelligence (iPhone 13 and older, for instance). Use the llama.cpp path.
    case deviceNotEligible
    /// The device can, but Apple Intelligence is off in Settings.
    case appleIntelligenceNotEnabled
    /// Apple Intelligence is on but the model is still downloading or preparing.
    case modelNotReady
    /// A reason this SDK doesn't know yet.
    case unknown(String)

    public var isAvailable: Bool { self == .available }

    /// A stable code for logs and settings JSON.
    public var code: String {
        switch self {
        case .available: "available"
        case .deviceNotEligible: "deviceNotEligible"
        case .appleIntelligenceNotEnabled: "appleIntelligenceNotEnabled"
        case .modelNotReady: "modelNotReady"
        case .unknown(let s): "unknown(\(s))"
        }
    }

    /// English, user-facing (the app localizes through its String Catalog with this as the key).
    public var userMessage: String {
        switch self {
        case .available: "Apple's on-device model is ready."
        case .deviceNotEligible: "This device doesn't support Apple Intelligence. BOAR will use a downloaded model instead."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to use Apple's on-device model."
        case .modelNotReady: "Apple's on-device model is still downloading. Try again in a few minutes."
        case .unknown: "Apple's on-device model isn't available right now."
        }
    }

    /// The user can fix it (turn the feature on, wait); `deviceNotEligible` is permanent.
    public var isTransient: Bool {
        switch self {
        case .appleIntelligenceNotEnabled, .modelNotReady, .unknown: true
        case .available, .deviceNotEligible: false
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available: self = .available
        case .unavailable(let reason): self.init(reason)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public init(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        switch reason {
        case .deviceNotEligible: self = .deviceNotEligible
        case .appleIntelligenceNotEnabled: self = .appleIntelligenceNotEnabled
        case .modelNotReady: self = .modelNotReady
        @unknown default: self = .unknown(String(describing: reason))
        }
    }

    /// The system model's state now.
    /// Before iOS 26 there is no system model: the device counts as not eligible.
    public static var current: AppleModelAvailability {
        guard #available(iOS 26.0, macOS 26.0, *) else { return .deviceNotEligible }
        return AppleModelAvailability(SystemLanguageModel.default.availability)
    }
}

// MARK: - Failures

/// The kinds of Foundation Models failure the UI treats differently. The session throws `ModelSeamError` (the seam contract);
/// `.generationFailed` messages start with `"<rawValue>: "`, so `AppleAIFailure.of(error)` recovers the kind.
public enum AppleAIFailure: String, Sendable, CaseIterable {
    /// The input or output tripped Apple's safety guardrails. Show "can't help with that", not a crash/retry message.
    case guardrailViolation = "guardrail violation"
    /// The model declined to answer (a refusal with an explanation).
    case refusal = "refusal"
    /// Instructions + history + prompt exceed the context window; trim history and retry.
    case contextWindowExceeded = "context window exceeded"
    case unsupportedLanguage = "unsupported language or locale"
    case rateLimited = "rate limited"
    case concurrentRequests = "concurrent requests"
    case assetsUnavailable = "model assets unavailable"
    case unavailable = "model unavailable"
    case decodingFailure = "decoding failure"
    case timeout = "timeout"
    case other = "apple model error"

    /// Guardrail or refusal: a safety block, not a fault.
    public var isSafetyBlock: Bool { self == .guardrailViolation || self == .refusal }

    public func seamError(_ detail: String) -> ModelSeamError {
        .generationFailed(detail.isEmpty ? rawValue : "\(rawValue): \(detail)")
    }

    /// The kind of a `ModelSeamError.generationFailed` thrown by `AppleSystemModel`; nil for anything else.
    public static func of(_ error: any Error) -> AppleAIFailure? {
        guard let seam = error as? ModelSeamError, case .generationFailed(let message) = seam else { return nil }
        // Longest raw value first so no kind shadows another.
        for kind in allCases.sorted(by: { $0.rawValue.count > $1.rawValue.count })
        where message == kind.rawValue || message.hasPrefix(kind.rawValue + ": ") {
            return kind
        }
        return nil
    }
}

/// Maps a Foundation Models error to the seam's `ModelSeamError`, keeping the failure kind recoverable.
public enum AppleAIErrorMapping {
    public static func map(_ error: any Error) -> ModelSeamError {
        if let seam = error as? ModelSeamError { return seam }
        if let kind = kind(of: error) { return kind.seamError(detail(of: error)) }
        return AppleAIFailure.other.seamError(String(describing: error))
    }

    /// The failure kind of a raw Foundation Models error (nil when it isn't one).
    public static func kind(of error: any Error) -> AppleAIFailure? {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            if let e = error as? LanguageModelError {
                switch e {
                case .contextSizeExceeded: return .contextWindowExceeded
                case .rateLimited: return .rateLimited
                case .guardrailViolation: return .guardrailViolation
                case .refusal: return .refusal
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                case .timeout: return .timeout
                case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide: return .other
                @unknown default: return .other
                }
            }
            if let e = error as? LanguageModelSession.Error {
                switch e {
                case .concurrentRequests: return .concurrentRequests
                default: return .other
                }
            }
            if let e = error as? SystemLanguageModel.Error {
                switch e {
                case .assetsUnavailable: return .assetsUnavailable
                @unknown default: return .other
                }
            }
        }
        if #available(iOS 26.0, macOS 26.0, *), let e = error as? LanguageModelSession.GenerationError {
            return legacyKind(e)
        }
        return nil
    }

    // The iOS 26 error enum (deprecated in 27, still thrown by the 26 runtime).
    @available(iOS, introduced: 26.0, deprecated: 27.0)
    @available(macOS, introduced: 26.0, deprecated: 27.0)
    private static func legacyKind(_ e: LanguageModelSession.GenerationError) -> AppleAIFailure {
        switch e {
        case .exceededContextWindowSize: .contextWindowExceeded
        case .assetsUnavailable: .assetsUnavailable
        case .guardrailViolation: .guardrailViolation
        case .unsupportedGuide: .other
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .decodingFailure: .decodingFailure
        case .rateLimited: .rateLimited
        case .concurrentRequests: .concurrentRequests
        case .refusal: .refusal
        @unknown default: .other
        }
    }

    private static func detail(of error: any Error) -> String {
        if let localized = error as? any LocalizedError, let d = localized.errorDescription, !d.isEmpty { return d }
        return String(describing: error)
    }
}
