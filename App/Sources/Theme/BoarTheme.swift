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
    /// The accent (Android's primary): buttons, toggles, links.
    var accent: Color { Color(emerald500) }
}

extension EnvironmentValues {
    /// The current theme palette; set by `.boarTheme(_:)` at the root.
    @Entry var palette: BoarPalette = .moonlight
}

/// Puts the chosen theme's palette in the environment, tints with its accent and sets the matching system appearance
/// (System: the device's, with Moonlight when dark and Paper when light).
private struct BoarThemeModifier: ViewModifier {
    let choice: ThemeChoice
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = choice.palette(dark: scheme == .dark)
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .preferredColorScheme(choice.colorScheme)
            #if os(iOS)
            // Alerts and confirmation dialogs are UIKit's and don't follow SwiftUI's tint: they would keep the asset's
            // AccentColor (Moonlight's amber) under Campfire.
            .onChange(of: palette.id, initial: true) {
                UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(palette.accent)
            }
            #endif
    }
}

extension View {
    /// The BOAR theme for this hierarchy (the root view, and each separate window or scene on the Mac).
    func boarTheme(_ choice: ThemeChoice) -> some View {
        modifier(BoarThemeModifier(choice: choice))
    }

    /// A brand text style by its Android name ("ui.body", "ui.titleLg", "mono.xs"): font, tracking and tabular digits.
    func boarText(_ name: String) -> some View {
        modifier(BoarTextModifier(name: name))
    }

    /// Baloo's tall ascent and descent spread a wrapped title's lines apart: pull them to about Android's 1.25 line
    /// height (iOS 26 and later; earlier systems keep the font's own spacing).
    @ViewBuilder func boarDisplayLines() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // The tighter line box also clips the block's own top and bottom: give that room back.
            lineHeight(.multiple(factor: 0.85))
                .padding(.vertical, 6)
        } else {
            self
        }
    }

    /// A form's text in the theme: Lexend at the body size, and the hierarchical styles (`.primary`, `.secondary`,
    /// `.tertiary`) in textPrimary, textSecondary and textDim, as Android's rows (BoarSection) are.
    func boarFormText() -> some View {
        modifier(BoarFormText())
    }

    /// A List on Android's screen background (bgTerminal) instead of the grouped system gray.
    func boarListBackground() -> some View {
        modifier(BoarListBackground())
    }

    /// The rows of a List section on Android's card color (bgCard).
    func boarRowBackground() -> some View {
        modifier(BoarRowBackground())
    }

    /// A List in Android's look on iPhone: the screen background and Lexend text; put its sections in `boarListRows()`.
    /// The Mac keeps its system list (a selectable sidebar beside the details).
    @ViewBuilder func boarList() -> some View {
        #if os(macOS)
        self
        #else
        boarListBackground()
            .font(.boar("ui.body"))
        #endif
    }

    /// A List's sections on Android's cards, with the subtle border as separator (iPhone; on the Mac custom row
    /// backgrounds would hide the selection).
    @ViewBuilder func boarListRows() -> some View {
        #if os(macOS)
        self
        #else
        modifier(BoarListRows())
        #endif
    }
}

/// A settings-style Form in Android's look (BoarSection: cards on the screen background, Lexend text), keeping the
/// system rows, toggles and pickers. Rows read in the theme's text colors (`.primary`, `.secondary` and `.tertiary`
/// become textPrimary, textSecondary and textDim); put each section title in a `BoarHeader` and each footer in a
/// `BoarFooter`.
struct BoarForm<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Color(palette.bgCard))
                .listRowSeparatorTint(Color(palette.borderSubtle))
        }
        .boarListBackground()
        .boarFormText()
    }
}

/// A theme color by its role, resolved from the palette in the environment, so a view can say
/// `.foregroundStyle(.boar(.danger))` where it used `.red`. On a prominent background (a selected row in the Mac's
/// sidebar lists, drawn in the system accent) text goes back to the system's `.primary` and `.secondary`, which turn
/// white there; a theme color would sink into the highlight.
///
/// Keep selectable lists (`List(selection:)`: the Mac's Models, Browse and Documents) outside `BoarForm` and
/// `GroupedList`: those redefine `.primary` and `.secondary` as theme colors, so this fallback would land on them.
struct BoarStyle: ShapeStyle {
    enum Role: Sendable {
        /// Android's crimson400: errors and destructive actions.
        case danger
        /// amber400: warnings ("almost full", a missing model).
        case warning
        /// textAccentAmber: time left on a download.
        case amber
        /// textAccentEmerald: success and "on" states.
        case success
        /// textAccentCyan: links and secondary actions (Android's LinkButton).
        case link
        /// emerald500, Android's primary: progress, toggles.
        case accent
        case heading, primary, secondary, muted
        /// textDim: the quietest line (sizes, file names).
        case dim
        /// borderDefault: rings and baselines drawn in a Canvas.
        case border
    }

    let role: Role

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        if environment.backgroundProminence == .increased {
            return switch role {
            case .heading, .primary: AnyShapeStyle(.primary)
            default: AnyShapeStyle(.secondary)
            }
        }
        return AnyShapeStyle(color(environment.palette))
    }

    private func color(_ p: BoarPalette) -> Color {
        switch role {
        case .danger: Color(p.crimson400)
        case .warning: Color(p.amber400)
        case .amber: Color(p.textAccentAmber)
        case .success: Color(p.textAccentEmerald)
        case .link: Color(p.textAccentCyan)
        case .accent: Color(p.emerald500)
        case .heading: Color(p.textHeading)
        case .primary: Color(p.textPrimary)
        case .secondary: Color(p.textSecondary)
        case .muted: Color(p.textMuted)
        case .dim: Color(p.textDim)
        case .border: Color(p.borderDefault)
        }
    }
}

extension ShapeStyle where Self == BoarStyle {
    /// A theme color by role (`.boar(.danger)`).
    static func boar(_ role: BoarStyle.Role) -> BoarStyle { BoarStyle(role: role) }
}

/// A Form section's title as Android's BoarSection writes it (BoarSection.kt): ui.title in the heading color, as
/// written (no small capitals).
struct BoarHeader<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.boar("ui.title"))
            .foregroundStyle(.boar(.heading))
            .textCase(nil)
    }
}

/// A Form section's footer as Android's notes under a setting: ui.subtext in the muted text color.
struct BoarFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.boar("ui.subtext"))
            .foregroundStyle(.boar(.muted))
    }
}

private struct BoarFormText: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.boar("ui.body"))
            .foregroundStyle(Color(palette.textPrimary), Color(palette.textSecondary), Color(palette.textDim))
            #if os(iOS)
            .buttonStyle(BoarFormButtonStyle())
            #endif
    }
}

/// An iPhone form's row buttons as the system draws them, in the tint (or crimson400 when destructive), and in textDim
/// when disabled: the form's text colors would otherwise win over the tint, and a row button would read like a row
/// title. The color is set on the label, so it also has to say "disabled" (the system only fades it, and a faded amber
/// still reads as a live button). A label's own style still wins. The Mac's push buttons keep their own look.
private struct BoarFormButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FormButton(configuration: configuration)
    }

    private struct FormButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.foregroundStyle(style)
            }
            .buttonStyle(.automatic)
        }

        private var style: AnyShapeStyle {
            if !isEnabled { return AnyShapeStyle(.boar(.dim)) }
            return configuration.role == .destructive ? AnyShapeStyle(.boar(.danger)) : AnyShapeStyle(.tint)
        }
    }
}

private struct BoarListBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color(palette.bgTerminal).ignoresSafeArea())
    }
}

private struct BoarListRows: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .listRowBackground(Color(palette.bgCard))
            .listRowSeparatorTint(Color(palette.borderSubtle))
    }
}

private struct BoarRowBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.listRowBackground(Color(palette.bgCard))
    }
}

private struct BoarTextModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        let style = BrandType.style(name, scale: "standard")
        content
            .font(.boar(name))
            .tracking(CGFloat(style?.letterSpacing ?? 0))
            .modifier(BoarLineHeight(style: style))
    }
}

/// Android's line height for a brand style. Lexend's own line is shorter than Android's (1.25× the size against
/// ui.bodyLg's 22 pt at 18 pt): the difference becomes line spacing. Baloo's is taller (1.6×): iOS/macOS 26 pull it in
/// with lineHeight and give the block's clipped top and bottom back; earlier systems keep the font's spacing.
/// The monospaced styles keep the system font's line.
private struct BoarLineHeight: ViewModifier {
    let style: BrandType.Style?

    func body(content: Content) -> some View {
        if let style, let target = style.lineHeight.map(CGFloat.init), style.face != .monospace, target > 0 {
            let natural = BrandFonts.lineHeight(style.face, size: CGFloat(style.size))
            let gap = target - natural
            if gap > 0.5 {
                content.lineSpacing(gap)
            } else if gap < -0.5 {
                if #available(iOS 26.0, macOS 26.0, *) {
                    content
                        .lineHeight(.multiple(factor: target / natural))
                        .padding(.vertical, (-gap / 2).rounded(.up))
                } else {
                    content
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// The prominent button with the theme's inverse text on the accent: SwiftUI writes white on the tint, which on
/// Moonlight's amber is ~1.8:1. The glass style is Liquid Glass on iOS/macOS 26 (the bordered one before).
struct BoarProminentButtonStyle: PrimitiveButtonStyle {
    var glass = false

    func makeBody(configuration: Configuration) -> some View {
        ThemedButton(configuration: configuration, glass: glass)
    }

    private struct ThemedButton: View {
        let configuration: Configuration
        let glass: Bool
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let button = Button(role: configuration.role, action: configuration.trigger) {
                configuration.label
                    .foregroundStyle(isEnabled ? AnyShapeStyle(Color(palette.textInverse)) : AnyShapeStyle(.secondary))
            }
            if glass, #available(iOS 26.0, macOS 26.0, *) {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == BoarProminentButtonStyle {
    /// `.borderedProminent` with the theme's inverse text.
    static var boarProminent: BoarProminentButtonStyle { BoarProminentButtonStyle() }
    /// `.glassProminent` (iOS/macOS 26; bordered before) with the theme's inverse text.
    static var boarGlassProminent: BoarProminentButtonStyle { BoarProminentButtonStyle(glass: true) }
}

/// Something to do about an answer (Try again, Allow more, Ask BOAR instead), in the accent: the emerald text on its
/// subtle background with its border, on a line of its own (android ChatScreen ActionButton).
struct BoarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(Color(palette.textAccentEmerald))
                .background(Color(palette.emeraldBgSubtle), in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(palette.emeraldBorder)))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .contentShape(.rect(cornerRadius: 10))
        }
    }
}

extension ButtonStyle where Self == BoarActionButtonStyle {
    /// An answer's action in the accent (android ActionButton).
    static var boarAction: BoarActionButtonStyle { BoarActionButtonStyle() }
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

    /// A brand style's face at a fixed size, as Android's `Boar.type["mono.xs"].copy(fontSize = 9.sp)` (the Labs' status
    /// tags): Lexend for the mono styles, with fixed-width digits. It doesn't grow with Dynamic Type, so a tag keeps
    /// fitting its tile.
    static func boar(_ name: String, size: CGFloat) -> Font {
        let style = BrandType.style(name, scale: "standard")
        let face = style?.face ?? .lexend400
        let font: Font = face == .monospace ? .system(size: size, design: .monospaced) : .custom(face.rawValue, fixedSize: size)
        return style?.tabular == true ? font.monospacedDigit() : font
    }

    /// Baloo 2 ExtraBold at an iOS title size (the editorial setup titles, larger than Android's 24 pt headline).
    static func boarDisplay(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(BrandType.Face.baloo800.rawValue, size: size, relativeTo: style)
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

    /// A brand face's own line height (ascent + descent + leading) at a size.
    static func lineHeight(_ face: BrandType.Face, size: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName(face.rawValue as CFString, size, nil)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

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
