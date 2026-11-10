import SwiftUI

/// One promise on the About screen: a symbol, a title and one secondary line.
struct AboutFeatureRow: View {
    let title: LocalizedStringKey
    let symbol: AppIcon
    let text: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                Text(text)
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(icon: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}
