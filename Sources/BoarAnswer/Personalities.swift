import BoarModels
import Foundation

/// An answer style. The texts are in `personalities.json`, copied from the Android app's assets, which is their source.
public struct Personality: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var icon: String
    public var description: String
    /// Unused for "custom": the user writes their own.
    public var systemPrompt: String
    /// Appended to the question: small models follow what is closest to it.
    public var styleReminder: String?
    /// For a small answer model (under `Personalities.smallModelBytes`): Detailed uses r4to's D1 here, without D4's "Always
    /// do what the user asks", which made the 1.5B follow first-aid asks with wrong steps in his engine tests (Oct 18).
    public var systemPromptSmall: String?
    public var styleReminderSmall: String?

    public init(
        id: String, label: String, icon: String, description: String, systemPrompt: String, styleReminder: String? = nil,
        systemPromptSmall: String? = nil, styleReminderSmall: String? = nil
    ) {
        self.id = id; self.label = label; self.icon = icon; self.description = description
        self.systemPrompt = systemPrompt; self.styleReminder = styleReminder
        self.systemPromptSmall = systemPromptSmall; self.styleReminderSmall = styleReminderSmall
    }
}

public struct Personalities: Codable, Sendable, Equatable {
    public var personalities: [Personality]
    public var defaultId: String
    public var maxTokensOptions: [Int]
    public var defaultMaxTokens: Int

    public init(personalities: [Personality], defaultId: String, maxTokensOptions: [Int], defaultMaxTokens: Int) {
        self.personalities = personalities; self.defaultId = defaultId
        self.maxTokensOptions = maxTokensOptions; self.defaultMaxTokens = defaultMaxTokens
    }

    /// Unknown ids fall back to the first style, as getPersonality does.
    public func get(_ id: String?) -> Personality { personalities.first { $0.id == id } ?? personalities[0] }

    /// Models smaller than this file size are "small" for `promptFor` (Qwen2.5 1.5B is 1.0 GB, Qwen3 4B 2.5 GB).
    public static let smallModelBytes: Int64 = 2_000_000_000

    /// The system prompt and style reminder for a setting; "custom" uses the user's prompt and no reminder. `smallModel`:
    /// the answer model is under `smallModelBytes`, and a style's small-model texts are used where it has them.
    public func promptFor(_ id: String?, customPrompt: String?, smallModel: Bool = false) -> (systemPrompt: String, styleReminder: String?) {
        let effective = id ?? defaultId
        if effective == "custom" { return (customPrompt ?? "", nil) }
        let p = get(effective)
        if smallModel, let small = p.systemPromptSmall { return (small, p.styleReminderSmall) }
        return (p.systemPrompt, p.styleReminder)
    }

    public static func parse(_ data: Data) throws -> Personalities { try JSONDecoder().decode(Personalities.self, from: data) }

    /// The `personalities.json` bundled with BoarModels.
    public static func bundled() throws -> Personalities { try parse(BoarData.data(.personalities)) }
}
