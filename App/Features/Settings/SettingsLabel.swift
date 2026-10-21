import SwiftUI

/// A Settings-app row title: a white SF Symbol on a small rounded square of one system color, then the title. The icons
/// let people find a setting by shape and color instead of reading every row.
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var side = 29

    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            // Every glyph fits the same inner box (about 60 % of the tile, as in the Settings app), so wide symbols
            // like "gearshape.2" don't fill their tile.
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: side * 0.6, height: side * 0.6)
                .frame(width: side, height: side)
                .background(color.gradient, in: .rect(cornerRadius: side * 0.24))
                .accessibilityHidden(true)
        }
    }
}
