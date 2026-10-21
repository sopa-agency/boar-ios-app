import BoarCore
import Foundation

// MARK: - Pure mapping from the BOAR model seam to Foundation Models
//
// Everything in this file is free of FoundationModels types so it can be unit-tested on any host. `AppleSystemModel` turns
// these plans into `Transcript` / `GenerationOptions` values.

/// How a `[ChatMessage]` request lands in a Foundation Models session.
///
/// - the FIRST `system` message becomes the session instructions; any later `system` message is appended to the instructions
///   (separated by a blank line), because Foundation Models has exactly one instructions entry;
/// - the LAST `user` message is the prompt the session responds to;
/// - every `user` / `assistant` turn before it is replayed as transcript history (prompt / response entries);
/// - an `assistant` message after the last `user` message (a pre-filled answer) is not expressible and is rejected.
public struct ApplePromptPlan: Sendable, Equatable {
    public enum Turn: Sendable, Equatable {
        case user(String)
        case assistant(String)
    }

    public var instructions: String?
    public var history: [Turn]
    public var prompt: String

    public init(instructions: String?, history: [Turn], prompt: String) {
        self.instructions = instructions; self.history = history; self.prompt = prompt
    }

    /// A stable key for "same instructions + same history" (prewarmed-session reuse).
    public var prefixKey: String {
        var parts = ["i:" + (instructions ?? "")]
        for t in history {
            switch t {
            case .user(let s): parts.append("u:" + s)
            case .assistant(let s): parts.append("a:" + s)
            }
        }
        return parts.joined(separator: "\u{1F}")
    }

    /// Maps a seam input. `.prompt` is rejected: Apple's model only takes role messages (`acceptsRawPrompt == false`).
    public static func make(_ input: GenerationRequest.Input) throws -> ApplePromptPlan {
        switch input {
        case .prompt:
            throw ModelSeamError.unsupportedInput("raw prompt: the Apple on-device model takes role messages only")
        case .messages(let messages):
            return try make(messages)
        }
    }

    public static func make(_ messages: [ChatMessage]) throws -> ApplePromptPlan {
        guard let lastUser = messages.lastIndex(where: { $0.role == .user }) else {
            throw ModelSeamError.unsupportedInput("no user message")
        }
        if messages[(lastUser + 1)...].contains(where: { $0.role != .system }) {
            throw ModelSeamError.unsupportedInput("assistant prefill after the last user message")
        }
        var systemParts: [String] = []
        var history: [Turn] = []
        for (i, m) in messages.enumerated() {
            switch m.role {
            case .system: systemParts.append(m.content)
            case .user where i < lastUser: history.append(.user(m.content))
            case .assistant: history.append(.assistant(m.content))
            case .user: break  // the prompt itself
            default:
                // Unknown roles ("tool", …) carry text the model should still see; replay them as user turns.
                if i < lastUser { history.append(.user(m.content)) }
            }
        }
        let instructions = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return ApplePromptPlan(instructions: instructions, history: history, prompt: messages[lastUser].content)
    }
}

/// `Sampling` → `GenerationOptions`, without FoundationModels types.
///
/// Foundation Models exposes one sampling mode, a temperature and a response-token cap. `topK`, `minP` and `repeatPenalty` have no
/// equivalent and are ignored (llama-only knobs). Mapping:
/// - `temperature <= 0` → greedy;
/// - `0 < topP < 1` → nucleus sampling with `probabilityThreshold = topP` (and the seed when `seed >= 0`);
/// - otherwise, a fixed seed alone → nucleus with threshold 1.0 so the seed applies; else the system default sampling;
/// - `nPredict > 0` → `maximumResponseTokens`; `nPredict <= 0` means "prefill only" and is handled as a prewarm by the session.
public struct AppleOptionsPlan: Sendable, Equatable {
    public enum SamplingPlan: Sendable, Equatable {
        case systemDefault
        case greedy
        case nucleus(threshold: Double, seed: UInt64?)
    }

    public var sampling: SamplingPlan
    public var temperature: Double?
    public var maximumResponseTokens: Int?

    public init(sampling: SamplingPlan, temperature: Double?, maximumResponseTokens: Int?) {
        self.sampling = sampling; self.temperature = temperature; self.maximumResponseTokens = maximumResponseTokens
    }

    public static func make(_ s: Sampling) -> AppleOptionsPlan {
        let seed: UInt64? = s.seed >= 0 ? UInt64(s.seed) : nil
        let sampling: SamplingPlan
        let temperature: Double?
        if s.temperature <= 0 {
            sampling = .greedy
            temperature = nil
        } else {
            temperature = Double(s.temperature)
            if s.topP > 0 && s.topP < 1 {
                sampling = .nucleus(threshold: Double(s.topP), seed: seed)
            } else if let seed {
                sampling = .nucleus(threshold: 1.0, seed: seed)
            } else {
                sampling = .systemDefault
            }
        }
        return AppleOptionsPlan(sampling: sampling, temperature: temperature, maximumResponseTokens: s.nPredict > 0 ? s.nPredict : nil)
    }
}

/// Turns cumulative stream snapshots (Foundation Models streams the whole text so far) into deltas.
public struct SnapshotDiffer: Sendable {
    public private(set) var previous = ""
    public init() {}

    /// The new text since the last snapshot. If the model rewrote earlier text (not expected for plain strings), already-emitted
    /// text can't be retracted: only the characters beyond the length already shown are returned.
    public mutating func delta(_ snapshot: String) -> String {
        defer { if snapshot.count >= previous.count { previous = snapshot } }
        return String(snapshot.dropFirst(previous.count))
    }
}

/// Why a generation ended, in the seam's vocabulary (`GenerationMetrics.stopReason`).
public enum AppleStopReason {
    public static func derive(hitStop: Bool, cancelled: Bool, generatedTokens: Int, maximumResponseTokens: Int?) -> String {
        if hitStop { return "stop" }
        if cancelled { return "cancelled" }
        if let cap = maximumResponseTokens, generatedTokens > 0, generatedTokens >= cap { return "length" }
        return "eos"
    }
}
