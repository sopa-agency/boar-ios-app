import SwiftUI

/// Settings → Display → Appearance: follow the system, or force light or dark. Stored in the engine's `themeId`
/// setting slot (older builds stored a theme name there, which reads as `.system`).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    init(storedId: String?) {
        self = storedId.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
