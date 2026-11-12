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

    /// The theme to show: a Boar Avatars theme only while Boarverse is on, else Android's default, Moonlight
    /// (`ThemeTokens.shows`). The stored id is left as it was.
    public func shown(boarverse: Bool) -> ThemeChoice {
        guard case .theme(let id) = self, !ThemeTokens.shows(id, boarverse: boarverse) else { return self }
        return .theme(ThemeTokens.defaultId)
    }

    /// The picker's choices: System, then the themes available (`ThemeTokens.available`), and the current one if it
    /// isn't among them (Paper set on Android or by an older build, a theme granted on another phone).
    public static func choices(current: ThemeChoice, available: [BoarPalette] = ThemeTokens.open) -> [ThemeChoice] {
        var list: [ThemeChoice] = [.system] + available.map { .theme($0.id) }
        if !list.contains(current) { list.append(current) }
        return list
    }
}
