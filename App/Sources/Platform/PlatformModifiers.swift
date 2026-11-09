import SwiftUI

/// SwiftUI APIs that exist only on iPhone/iPad, with their Mac counterpart, so each screen writes one line.
extension View {
    /// Inline (small) navigation title on iPhone; the Mac's window toolbar has one title style.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// The grouped list with rounded sections on iPhone; the inset list on the Mac.
    func groupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// Grouped forms everywhere: the iPhone look on iOS, the System Settings look on the Mac (instead of label columns).
    func groupedFormStyle() -> some View {
        formStyle(.grouped)
    }

    /// Tight spacing between list sections (iPhone only; the Mac list has no section gaps to tighten).
    func compactSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
        #else
        self
        #endif
    }
}

extension View {
    /// Keeps a list or form at a readable width in the middle of a wide Mac window; nothing changes on iPhone and iPad.
    func readableWidth(_ max: CGFloat = 680) -> some View {
        #if os(macOS)
        modifier(ReadableWidth(max: max))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct ReadableWidth: ViewModifier {
    let max: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: max)
            .frame(maxWidth: .infinity)
    }
}
#endif

extension View {
    /// A sheet's size on the Mac, where a sheet has no size of its own and a List in it collapses to nothing.
    func macSheetSize(width: CGFloat = 480, height: CGFloat = 520) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }
}

extension SearchFieldPlacement {
    /// The search field always visible under the title on iPhone; the toolbar's field on the Mac.
    static var alwaysVisible: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .toolbar
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The leading edge of the bar (top-left on iPhone, before the title on the Mac).
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}

extension Color {
    /// The screen's base background (white / black on iPhone, the window background on the Mac).
    static var baseBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// The primary text color as a fill.
    static var labelColor: Color {
        #if canImport(UIKit)
        Color(uiColor: .label)
        #else
        Color(nsColor: .labelColor)
        #endif
    }
}

// MARK: - iOS 26 design APIs with iOS 18 fallbacks

extension View {
    /// Liquid Glass on iOS 26 and later; the regular material (the iOS 18 look) before.
    @ViewBuilder func glassOrMaterial<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// The prominent glass button on iOS 26; the bordered prominent button before. Both with the theme's inverse text.
    func prominentGlassButtonStyle() -> some View {
        buttonStyle(.boarGlassProminent)
    }

    /// A bar pinned to the bottom edge: `safeAreaBar` on iOS 26 (the content scrolls under it), `safeAreaInset` before.
    @ViewBuilder func bottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: bar)
        } else {
            safeAreaInset(edge: .bottom, content: bar)
        }
    }

    /// The navigation subtitle (iOS 26); before iOS 26 the bar has a title only.
    @ViewBuilder func navigationSubtitleIfAvailable(_ subtitle: Text) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

/// The sheet's close button: the system close role on iOS 26, an "xmark" button before.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(role: .close, action: action)
        } else {
            Button("Close", systemImage: "xmark", action: action)
        }
    }
}
