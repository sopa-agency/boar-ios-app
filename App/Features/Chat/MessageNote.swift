import SwiftUI

/// A note on an answer: stopped by the user, or a research step cut short (a warning).
struct MessageNote: View {
    let symbol: AppIcon
    let text: LocalizedStringKey
    let warning: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(icon: symbol).foregroundStyle(warning ? .orange : .secondary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
