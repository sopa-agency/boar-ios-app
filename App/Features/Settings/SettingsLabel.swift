import SwiftUI

/// A Settings row title with its icon, as Android's Settings draws them (BoarSection, the Boar icon pack): a one-color
/// glyph in the heading color, then the title. The SF Symbol stands in for the pack's
/// drawable; every glyph fits the same box, so the titles line up.
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    @ScaledMetric(relativeTo: .body) private var side = 24

    init(_ title: LocalizedStringKey, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.boar(.heading))
                .frame(width: side * 0.9, height: side * 0.9)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}
