import BoarCore
import SwiftUI

extension ThemeChoice {
    /// The picker's label: Android's chip text ("🔥 Campfire") for a theme.
    var title: Text {
        switch self {
        case .system: Text("System")
        case .theme(let id): Text(verbatim: "\(ThemeTokens.byId(id).icon) \(ThemeTokens.byId(id).name)")
        }
    }

    /// The system appearance to show: System follows the device (nil); a theme brings its own (Paper light, the others
    /// dark), so the system's controls, sheets and status bar match its colors.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .theme(let id): ThemeTokens.byId(id).light ? .light : .dark
        }
    }
}
