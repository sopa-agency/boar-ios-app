import Foundation

/// Who BOAR is set up for (android `UserProfile`, rc3): Starter (id `simple`) shows only the settings everyone needs,
/// Explorer adds how BOAR answers and what it keeps, Pro adds the technical corner. Each profile shows everything the one
/// before it does. A fresh install starts on Starter; an install from before profiles gets its profile once from
/// `forUpdate`.
public enum UserProfile: String, CaseIterable, Sendable {
    case simple, explorer, pro

    /// The stored key (android `key`).
    public var key: String { rawValue }

    public func includes(_ other: UserProfile) -> Bool { ordinal >= other.ordinal }

    /// Position in the order Starter, Explorer, Pro (android `ordinal`).
    public var ordinal: Int { Self.allCases.firstIndex(of: self)! }

    public static let `default` = UserProfile.simple

    public static func of(_ key: String?) -> UserProfile? { allCases.first { $0.key == key } }

    /// The profile for an install that has settings from before profiles: the lowest one that still shows everything the
    /// user changed, so nothing they chose is hidden or switched off. `proChanged`: something only Pro shows (an Advanced
    /// tweak, adaptive routing, the free-memory delay, the debug log, a lab switched on). `explorerChanged`: something
    /// Explorer shows (a style, an answer length, haptics, dictation off, a chat-history option, Boarverse on). Technical
    /// details on (the old default) is not a sign.
    public static func forUpdate(proChanged: Bool, explorerChanged: Bool) -> UserProfile {
        if proChanged { return .pro }
        if explorerChanged { return .explorer }
        return .simple
    }
}

/// Each Settings section, or row inside one, and the first profile that shows it (android `SettingsPart`). A part not
/// listed here would show for nobody, so every part has a profile. Some parts are Android's own and have no row on iOS
/// (`language`, `textSize`, `orientation`: the system sets them); they keep their profile so the table stays Android's.
public enum SettingsPart: CaseIterable, Sendable {
    case profile, language, theme, textSize, security, recovery
    case tone, memory, voice, avatars, boarverseSwitch, orientation, haptics
    case tweaks, technicalDetails, telemetry, labsSettings
    /// Advanced tweaks → Staged quotes: the fallback switch for Staged answers (core since Nov 12).
    case stagedQuotes
    case adaptiveRouting

    public var from: UserProfile {
        switch self {
        case .profile, .language, .theme, .textSize, .security, .recovery: .simple
        case .tone, .memory, .voice, .avatars, .boarverseSwitch, .orientation, .haptics: .explorer
        case .tweaks, .technicalDetails, .telemetry, .labsSettings, .stagedQuotes, .adaptiveRouting: .pro
        }
    }

    public func shown(in profile: UserProfile) -> Bool { profile.includes(from) }

    /// The Experimental section shows when any of its rows does.
    public static let experimentalRows: [SettingsPart] = [.boarverseSwitch, .labsSettings, .adaptiveRouting]
    public static func experimentalShown(in profile: UserProfile) -> Bool { experimentalRows.contains { $0.shown(in: profile) } }
}
