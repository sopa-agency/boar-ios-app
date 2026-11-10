import SwiftUI

/// A Settings row title with its icon, as Android's Settings draws them (BoarSection, the Boar icon pack): a one-color
/// glyph in the heading color, then the title. The pack's glyph where Android's section has one, an SF Symbol for the
/// rows Android doesn't have; every glyph fits the same box, so the titles line up.
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let symbol: AppIcon
    @ScaledMetric(relativeTo: .body) private var side = 24
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, symbol: AppIcon) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(icon: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.boar(.heading))
                .opacity(isEnabled ? 1 : 0.4)
                .frame(width: side * 0.9, height: side * 0.9)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}
