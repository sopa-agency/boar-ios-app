import BoarCore
import CoreText
import os
import SwiftUI

// Android's look (ui/theme) in SwiftUI: the palette of the current color scheme in the environment, and the brand fonts
// (Baloo 2 for titles, Lexend for reading) at Dynamic Type sizes. Views read colors as `palette.bgCard`, never literals.

extension Color {
    /// A theme token (0xAARRGGBB, sRGB).
    init(_ c: ARGB) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

extension BoarPalette {
    /// The palette for the system's (or Settings') appearance: Moonlight, Android's default, when dark; Paper, Android's
    /// light theme, when light. Campfire and the Vault's themes come with a theme picker.
    static func forScheme(_ scheme: ColorScheme) -> BoarPalette {
        scheme == .dark ? .moonlight : .paper
    }

    /// wash: white on the dark themes, black on a light one, for chips and round buttons.
    func washColor(_ alpha: Double) -> Color {
        (light ? Color.black : Color.white).opacity(alpha)
    }

    /// The accent (Android's primary): buttons, toggles, links.
    var accent: Color { Color(emerald500) }
}

extension EnvironmentValues {
    /// The current theme palette; set by `.boarTheme()` at the root.
    @Entry var palette: BoarPalette = .moonlight
}

/// Puts the palette for the current color scheme in the environment and tints with its accent.
private struct BoarThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = BoarPalette.forScheme(scheme)
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
    }
}

extension View {
    /// The BOAR theme for this hierarchy (the root view, and each separate window or scene on the Mac).
    func boarTheme() -> some View {
        modifier(BoarThemeModifier())
    }

    /// A brand text style by its Android name ("ui.body", "ui.titleLg", "mono.xs"): font, tracking and tabular digits.
    func boarText(_ name: String) -> some View {
        modifier(BoarTextModifier(name: name))
    }
}

private struct BoarTextModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        let style = BrandType.style(name, scale: "standard")
        content
            .font(.boar(name))
            .tracking(CGFloat(style?.letterSpacing ?? 0))
    }
}

extension Font {
    /// A brand text style by its Android name at the Standard size, scaled with Dynamic Type like the text style it
    /// stands for. Text size follows the system on iOS (Android's Settings → Text size isn't offered).
    static func boar(_ name: String) -> Font {
        guard let style = BrandType.style(name, scale: "standard") else { return .body }
        let size = CGFloat(style.size)
        let relative = relativeStyle(name)
        let font: Font = style.face == .monospace
            ? .system(size: size, design: .monospaced)
            : .custom(style.face.rawValue, size: size, relativeTo: relative)
        return style.tabular ? font.monospacedDigit() : font
    }

    /// The system text style each brand style grows with under Dynamic Type.
    private static func relativeStyle(_ name: String) -> Font.TextStyle {
        switch name {
        case "ui.headline": .title
        case "ui.titleLg": .title2
        case "ui.title": .title3
        case "ui.titleSm": .headline
        case "ui.body", "ui.bodyLg": .body
        case "ui.subtext", "mono.base": .subheadline
        case "ui.caption", "mono.sm", "mono.md": .footnote
        case "ui.micro", "mono.xs": .caption
        default: .body
        }
    }
}

/// Registers the bundled Baloo 2 and Lexend faces (App/Resources/Fonts, SIL OFL 1.1) for this process.
enum BrandFonts {
    private static let log = Logger(subsystem: "team.sopa.boar", category: "theme")
    @MainActor private static var registered = false

    @MainActor static func register() {
        guard !registered else { return }
        registered = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        guard !urls.isEmpty else {
            log.error("brand fonts: no .ttf in the bundle")
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            for error in errors as? [CFError] ?? [] {
                log.error("brand font: \(error.localizedDescription, privacy: .public)")
            }
            return true
        }
    }
}
