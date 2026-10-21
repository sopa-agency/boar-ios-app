import BoarModels
import Foundation

/// An answer style (port of src/constants/personalities.ts). The texts come from the TypeScript source through
/// `personalities.json`, so every app sends the same prompts.
public struct Personality: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var icon: String
    public var description: String
    /// Unused for "custom": the user writes their own.
    public var systemPrompt: String
    /// Appended to the question: small models follow what is closest to it.
    public var styleReminder: String?

    public init(id: String, label: String, icon: String, description: String, systemPrompt: String, styleReminder: String? = nil) {
        self.id = id; self.label = label; self.icon = icon; self.description = description
        self.systemPrompt = systemPrompt; self.styleReminder = styleReminder
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

    /// The system prompt and style reminder for a setting; "custom" uses the user's prompt and no reminder.
    public func promptFor(_ id: String?, customPrompt: String?) -> (systemPrompt: String, styleReminder: String?) {
        let effective = id ?? defaultId
        if effective == "custom" { return (customPrompt ?? "", nil) }
        let p = get(effective)
        return (p.systemPrompt, p.styleReminder)
    }

    public static func parse(_ data: Data) throws -> Personalities { try JSONDecoder().decode(Personalities.self, from: data) }

    /// The `personalities.json` bundled with BoarModels.
    public static func bundled() throws -> Personalities { try parse(BoarData.data(.personalities)) }
}
