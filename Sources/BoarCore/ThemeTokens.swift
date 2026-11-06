// Port of Android's ui/theme/ThemeTokens.kt, ExtraThemes.kt (Paper) and the pure part of Theme.kt (BrandType).
// Pure data: the app turns these into SwiftUI colors and fonts (App/Sources/Theme). The palettes themselves are
// generated into ThemePalettes.swift by scripts/export-theme-tokens.py.

/// A color as Android writes it: 0xAARRGGBB.
public struct ARGB: Sendable, Hashable, CustomStringConvertible {
    public let value: UInt32
    public init(_ value: UInt32) { self.value = value }

    public var alpha: Double { Double((value >> 24) & 0xFF) / 255 }
    public var red: Double { Double((value >> 16) & 0xFF) / 255 }
    public var green: Double { Double((value >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(value & 0xFF) / 255 }

    /// "#AARRGGBB", the fixture's spelling.
    public var description: String {
        let hex = String(value, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }
}

/// One theme's color tokens (BoarColors), named by their path: bg.card -> bgCard, emerald[500] -> emerald500.
public struct BoarPalette: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let icon: String
    /// A light theme (Paper): dark text on white.
    public let light: Bool
    public let bgBlack, bgTerminal, bgSurface, bgCard, bgCardElevated, bgCardHover, bgInput, bgSubtle, bgOverlay,
        bgModalOverlay: ARGB
    public let borderSubtle, borderDefault, borderElevated, borderFocus, borderEmerald, borderCyan, borderAmber,
        borderDanger, borderFrontier: ARGB
    public let textPrimary, textHeading, textSecondary, textMuted, textDim, textInverse, textAccentEmerald,
        textAccentCyan, textAccentAmber, textAccentViolet: ARGB
    public let emerald50, emerald400, emerald500, emerald600, emerald900, emeraldBgSubtle, emeraldBorder: ARGB
    public let cyan400, cyan500, cyan600, cyanBgSubtle, cyanBorder: ARGB
    public let frontierGlow, frontierGlowCyan, frontierBadgeBg, frontierBadgeBorder, frontierText,
        frontierGradientStart, frontierGradientEnd: ARGB
    public let amber400, amber500, amber600, amberBgSubtle, amberBorder: ARGB
    public let crimson400, crimson500, crimson600, crimson900, crimsonBgSubtle, crimsonBorder: ARGB

    public init(
        id: String, name: String, icon: String, light: Bool,
        bgBlack: ARGB, bgTerminal: ARGB, bgSurface: ARGB, bgCard: ARGB, bgCardElevated: ARGB, bgCardHover: ARGB,
        bgInput: ARGB, bgSubtle: ARGB, bgOverlay: ARGB, bgModalOverlay: ARGB,
        borderSubtle: ARGB, borderDefault: ARGB, borderElevated: ARGB, borderFocus: ARGB, borderEmerald: ARGB,
        borderCyan: ARGB, borderAmber: ARGB, borderDanger: ARGB, borderFrontier: ARGB,
        textPrimary: ARGB, textHeading: ARGB, textSecondary: ARGB, textMuted: ARGB, textDim: ARGB, textInverse: ARGB,
        textAccentEmerald: ARGB, textAccentCyan: ARGB, textAccentAmber: ARGB, textAccentViolet: ARGB,
        emerald50: ARGB, emerald400: ARGB, emerald500: ARGB, emerald600: ARGB, emerald900: ARGB,
        emeraldBgSubtle: ARGB, emeraldBorder: ARGB,
        cyan400: ARGB, cyan500: ARGB, cyan600: ARGB, cyanBgSubtle: ARGB, cyanBorder: ARGB,
        frontierGlow: ARGB, frontierGlowCyan: ARGB, frontierBadgeBg: ARGB, frontierBadgeBorder: ARGB,
        frontierText: ARGB, frontierGradientStart: ARGB, frontierGradientEnd: ARGB,
        amber400: ARGB, amber500: ARGB, amber600: ARGB, amberBgSubtle: ARGB, amberBorder: ARGB,
        crimson400: ARGB, crimson500: ARGB, crimson600: ARGB, crimson900: ARGB, crimsonBgSubtle: ARGB,
        crimsonBorder: ARGB
    ) {
        self.id = id; self.name = name; self.icon = icon; self.light = light
        self.bgBlack = bgBlack; self.bgTerminal = bgTerminal; self.bgSurface = bgSurface; self.bgCard = bgCard
        self.bgCardElevated = bgCardElevated; self.bgCardHover = bgCardHover; self.bgInput = bgInput
        self.bgSubtle = bgSubtle; self.bgOverlay = bgOverlay; self.bgModalOverlay = bgModalOverlay
        self.borderSubtle = borderSubtle; self.borderDefault = borderDefault; self.borderElevated = borderElevated
        self.borderFocus = borderFocus; self.borderEmerald = borderEmerald; self.borderCyan = borderCyan
        self.borderAmber = borderAmber; self.borderDanger = borderDanger; self.borderFrontier = borderFrontier
        self.textPrimary = textPrimary; self.textHeading = textHeading; self.textSecondary = textSecondary
        self.textMuted = textMuted; self.textDim = textDim; self.textInverse = textInverse
        self.textAccentEmerald = textAccentEmerald; self.textAccentCyan = textAccentCyan
        self.textAccentAmber = textAccentAmber; self.textAccentViolet = textAccentViolet
        self.emerald50 = emerald50; self.emerald400 = emerald400; self.emerald500 = emerald500
        self.emerald600 = emerald600; self.emerald900 = emerald900; self.emeraldBgSubtle = emeraldBgSubtle
        self.emeraldBorder = emeraldBorder
        self.cyan400 = cyan400; self.cyan500 = cyan500; self.cyan600 = cyan600; self.cyanBgSubtle = cyanBgSubtle
        self.cyanBorder = cyanBorder
        self.frontierGlow = frontierGlow; self.frontierGlowCyan = frontierGlowCyan
        self.frontierBadgeBg = frontierBadgeBg; self.frontierBadgeBorder = frontierBadgeBorder
        self.frontierText = frontierText; self.frontierGradientStart = frontierGradientStart
        self.frontierGradientEnd = frontierGradientEnd
        self.amber400 = amber400; self.amber500 = amber500; self.amber600 = amber600
        self.amberBgSubtle = amberBgSubtle; self.amberBorder = amberBorder
        self.crimson400 = crimson400; self.crimson500 = crimson500; self.crimson600 = crimson600
        self.crimson900 = crimson900; self.crimsonBgSubtle = crimsonBgSubtle; self.crimsonBorder = crimsonBorder
    }

    /// Every token by its Kotlin name, in declaration order (for the parity test and debugging).
    public var tokens: [(name: String, color: ARGB)] {
        Mirror(reflecting: self).children.compactMap { child in
            guard let name = child.label, let color = child.value as? ARGB else { return nil }
            return (name, color)
        }
    }

    /// wash: a faint wash over the background for chips and buttons, white on the dark themes, black on a light one
    /// (alpha 0...1).
    public func wash(_ alpha: Double) -> (white: Double, alpha: Double) { (light ? 0 : 1, alpha) }

    /// track: a meter's empty track, black at `alpha` on the dark themes, at 0.08 on a light one.
    public func trackAlpha(_ alpha: Double) -> Double { light ? 0.08 : alpha }
}

/// ThemeTokens + Themes: the palettes by id. The derived extras that the Truffle Vault unlocks (Tactical Red, Hacker
/// Green, ...) mix colors in Oklab and come with the Vault's port.
public enum ThemeTokens {
    public static let defaultId = "moonlight"
    /// Campfire and Moonlight, open to everyone.
    public static let open: [BoarPalette] = [.campfire, .moonlight]
    public static let all: [BoarPalette] = [.campfire, .moonlight, .paper]

    public static func byId(_ id: String?) -> BoarPalette {
        all.first { $0.id == id } ?? .moonlight
    }
}

/// spacing.ts
public enum Spacing {
    public static let xxs: Double = 2
    public static let xs: Double = 4
    public static let sm: Double = 8
    public static let md: Double = 12
    public static let base: Double = 16
    public static let lg: Double = 20
    public static let xl: Double = 24
    public static let xxl: Double = 32
    public static let xxxl: Double = 40
}

/// spacing.ts radii
public enum Radii {
    public static let xs: Double = 4
    public static let sm: Double = 6
    public static let md: Double = 8
    public static let lg: Double = 12
    public static let xl: Double = 16
    public static let xxl: Double = 24
    public static let full: Double = 9999
}

/// typography.ts: size, line height and weight per text style, per text-size setting. Sizes are Kotlin Floats.
public struct TextSpec: Sendable, Hashable {
    public let family: String
    public let size: Float
    public let lineHeight: Float?
    public let weight: Int
    public let letterSpacing: Float?

    public init(_ family: String, _ size: Float, _ lineHeight: Float?, _ weight: Int, _ letterSpacing: Float?) {
        self.family = family; self.size = size; self.lineHeight = lineHeight; self.weight = weight
        self.letterSpacing = letterSpacing
    }
}

public enum TypeTokens {
    public static let scales = ["compact", "standard", "large"]

    public static let compact: [String: TextSpec] = [
        "mono.xs": TextSpec("monospace", 9.25, 13, 400, 0.5),
        "mono.sm": TextSpec("monospace", 10.875, 14.5, 400, 0.25),
        "mono.base": TextSpec("monospace", 11.5, 16, 400, nil),
        "mono.md": TextSpec("monospace", 13.5, 18, 600, nil),
        "mono.lg": TextSpec("monospace", 16.5, 22, 700, nil),
        "ui.micro": TextSpec("sans-serif", 9.25, 12, 600, nil),
        "ui.caption": TextSpec("sans-serif", 10, 13.5, 500, nil),
        "ui.subtext": TextSpec("sans-serif", 11, 14, 400, nil),
        "ui.body": TextSpec("sans-serif", 12.5, 19, 400, nil),
        "ui.bodyLg": TextSpec("sans-serif", 13.5, 20, 400, nil),
        "ui.titleSm": TextSpec("display", 12.5, 16, 700, nil),
        "ui.title": TextSpec("display", 14.5, 20, 700, nil),
        "ui.titleLg": TextSpec("display", 18.5, 24, 800, nil),
        "ui.headline": TextSpec("display", 22.5, 28, 900, -0.3),
    ]

    public static let standard: [String: TextSpec] = [
        "mono.xs": TextSpec("monospace", 10, 14, 400, 0.5),
        "mono.sm": TextSpec("monospace", 12, 16, 400, 0.25),
        "mono.base": TextSpec("monospace", 13, 18, 400, nil),
        "mono.md": TextSpec("monospace", 15, 20, 600, nil),
        "mono.lg": TextSpec("monospace", 18, 24, 700, nil),
        "ui.micro": TextSpec("sans-serif", 10, 13, 600, nil),
        "ui.caption": TextSpec("sans-serif", 11, 15, 500, nil),
        "ui.subtext": TextSpec("sans-serif", 12, 16, 400, nil),
        "ui.body": TextSpec("sans-serif", 14, 21, 400, nil),
        "ui.bodyLg": TextSpec("sans-serif", 15, 22, 400, nil),
        "ui.titleSm": TextSpec("display", 14, 18, 700, nil),
        "ui.title": TextSpec("display", 16, 22, 700, nil),
        "ui.titleLg": TextSpec("display", 20, 26, 800, nil),
        "ui.headline": TextSpec("display", 24, 30, 900, -0.3),
    ]

    public static let large: [String: TextSpec] = [
        "mono.xs": TextSpec("monospace", 11.5, 16, 400, 0.5),
        "mono.sm": TextSpec("monospace", 14.25, 19, 400, 0.25),
        "mono.base": TextSpec("monospace", 16, 22, 400, nil),
        "mono.md": TextSpec("monospace", 18, 24, 600, nil),
        "mono.lg": TextSpec("monospace", 21, 28, 700, nil),
        "ui.micro": TextSpec("sans-serif", 11.5, 15, 600, nil),
        "ui.caption": TextSpec("sans-serif", 13.25, 18, 500, nil),
        "ui.subtext": TextSpec("sans-serif", 15, 20, 400, nil),
        "ui.body": TextSpec("sans-serif", 17, 25, 400, nil),
        "ui.bodyLg": TextSpec("sans-serif", 18, 26, 400, nil),
        "ui.titleSm": TextSpec("display", 17, 22, 700, nil),
        "ui.title": TextSpec("display", 19, 26, 700, nil),
        "ui.titleLg": TextSpec("display", 23, 30, 800, nil),
        "ui.headline": TextSpec("display", 27, 34, 900, -0.3),
    ]

    public static func specs(_ scale: String?) -> [String: TextSpec] {
        switch scale {
        case "compact": compact
        case "large": large
        default: standard
        }
    }
}

/// Brand type (Theme.kt BrandType): Baloo 2 for titles and weight 800+, Lexend at the nearest weight for everything
/// read, the platform monospace only for code. Math in Float, as Kotlin does it, so the sizes round the same way.
public enum BrandType {
    /// The bundled faces, by PostScript name (App/Resources/Fonts).
    public enum Face: String, Sendable, CaseIterable {
        case baloo700 = "Baloo2-Bold"
        case baloo800 = "Baloo2-ExtraBold"
        case lexend400 = "Lexend-Regular"
        case lexend500 = "Lexend-Medium"
        case lexend600 = "Lexend-SemiBold"
        case lexend700 = "Lexend-Bold"
        /// The platform monospace (code).
        case monospace = ""
    }

    /// Body size for text that sets none.
    public static let body = 16

    /// familyFor: the bundled face for a style's family and weight, and whether digits are fixed-width.
    public static func familyFor(_ family: String?, weight: Int) -> (face: Face, tabular: Bool) {
        if family == "code" { return (.monospace, false) }
        let mono = family == "monospace"
        if family == "display" || weight >= 800 { return (weight >= 800 ? .baloo800 : .baloo700, false) }
        let face: Face = switch weight {
        case 700...: .lexend700
        case 600...: .lexend600
        case 500...: .lexend500
        default: .lexend400
        }
        return (face, mono)
    }

    /// scaledSize: the new UI's scale (body 16, nothing under 12); titles keep their size.
    public static func scaledSize(_ size: Float) -> Float {
        if size <= 11 { return 12 }
        if size == 12 { return 13 }
        if size == 13 { return 14 }
        if size <= 15 { return 16 }
        return size
    }

    /// fontScaleFactor: the Settings text size.
    public static func factor(_ scale: String?) -> Float {
        switch scale {
        case "compact": 0.9
        case "large": 1.2
        default: 1
        }
    }

    /// A resolved text style: point size, line height and tracking in points.
    public struct Style: Sendable, Hashable {
        public let face: Face
        public let tabular: Bool
        public let size: Int
        public let lineHeight: Int?
        /// Kotlin sets `(letterSpacing / size).em`, which is `letterSpacing` points.
        public let letterSpacing: Float?
    }

    /// brandStyle for a TextSpec at a text-size setting.
    public static func style(_ spec: TextSpec, scale: String?) -> Style {
        let (face, tabular) = familyFor(spec.family, weight: spec.weight)
        let size = roundToInt(scaledSize(spec.size) * factor(scale))
        let line = spec.lineHeight.map { lh in
            spec.size > 0 ? roundToInt(lh * Float(size) / spec.size) : roundToInt(lh)
        }
        return Style(face: face, tabular: tabular, size: size, lineHeight: line, letterSpacing: spec.letterSpacing)
    }

    /// The named style ("ui.body", "mono.sm") at a text-size setting; nil for an unknown name.
    public static func style(_ name: String, scale: String?) -> Style? {
        TypeTokens.specs(scale)[name].map { style($0, scale: scale) }
    }

    /// Kotlin's Float.roundToInt (Math.round: half up).
    static func roundToInt(_ x: Float) -> Int { Int((x + 0.5).rounded(.down)) }
}
