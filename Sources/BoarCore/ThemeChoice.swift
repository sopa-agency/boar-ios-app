/// Settings → Display → Theme: one of Android's themes, stored in `themeId` under Android's id, or System, an iOS extra
/// that follows the device's appearance (Moonlight when dark, Paper when light) and is stored as "system", which Android
/// reads as its default, Moonlight.
public enum ThemeChoice: Hashable, Sendable, Identifiable {
    case system
    case theme(String)

    public static let systemId = "system"

    public var id: String { storedId }

    /// Unset follows the device (the iOS default). "light" and "dark" are what builds before Nov 7, 2026 stored; an id
    /// this app has no palette for (a Vault theme set on Android) falls back like Android's lookup, to Moonlight.
    public init(storedId: String?) {
        switch storedId {
        case nil, Self.systemId?: self = .system
        case "light"?: self = .theme(BoarPalette.paper.id)
        case "dark"?: self = .theme(BoarPalette.moonlight.id)
        case let id?: self = .theme(ThemeTokens.byId(id).id)
        }
    }

    public var storedId: String {
        switch self {
        case .system: Self.systemId
        case .theme(let id): id
        }
    }

    /// The palette to draw with; `dark` is the device's appearance, which only System looks at.
    public func palette(dark: Bool) -> BoarPalette {
        switch self {
        case .system: dark ? .moonlight : .paper
        case .theme(let id): ThemeTokens.byId(id)
        }
    }

    /// The picker's choices: System, then the open themes (Campfire, Moonlight). Paper and the Vault's themes open with
    /// an avatar on Android and the iOS app has no Vault yet, so a theme outside the open ones is listed only while it is
    /// the current choice (set on Android, or Light from an older build).
    public static func choices(current: ThemeChoice) -> [ThemeChoice] {
        var list: [ThemeChoice] = [.system] + ThemeTokens.open.map { .theme($0.id) }
        if !list.contains(current) { list.append(current) }
        return list
    }
}
