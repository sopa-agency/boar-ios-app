import SwiftUI

/// An icon: one of Android's Boar icon pack where Android draws one, an SF Symbol where it has none (AGENTS.md). The
/// pack's glyphs are custom symbols (Assets.xcassets/Icons, from scripts/import-icon-pack.py), so both kinds scale
/// with the text, sit on the baseline and take the tint the same way. A string literal names an SF Symbol;
/// `.pack(.menu)` names the pack's.
struct AppIcon: Hashable, Sendable, ExpressibleByStringLiteral {
    private enum Source: Hashable, Sendable {
        case system(String)
        case pack(BoarIcon)
    }

    private let source: Source

    init(stringLiteral name: String) {
        source = .system(name)
    }

    /// An SF Symbol by name.
    init(system name: String) {
        source = .system(name)
    }

    private init(_ icon: BoarIcon) {
        source = .pack(icon)
    }

    /// A glyph of Android's Boar icon pack.
    static func pack(_ icon: BoarIcon) -> AppIcon {
        AppIcon(icon)
    }

    var image: Image {
        switch source {
        case .system(let name): Image(systemName: name)
        case .pack(let icon): Image(icon.symbolName)
        }
    }
}

extension BoarIcon {
    /// The custom symbol's name in the asset catalog.
    var symbolName: String { "boar.\(rawValue)" }
}

extension Image {
    init(icon: AppIcon) {
        self = icon.image
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: LocalizedStringKey, icon: AppIcon) {
        self.init { Text(title) } icon: { icon.image }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: AppIcon) {
        self.init { Text(title) } icon: { icon.image }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ title: LocalizedStringKey, icon: AppIcon, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, icon: icon) }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: AppIcon, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, icon: icon) }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: LocalizedStringKey, icon: AppIcon, description: Text? = nil) {
        self.init { SwiftUI.Label(title, icon: icon) } description: { description }
    }
}
