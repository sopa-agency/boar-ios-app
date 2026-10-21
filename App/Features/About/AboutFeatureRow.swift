import SwiftUI

/// One promise on the About screen: a symbol, a title and one secondary line.
struct AboutFeatureRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}
