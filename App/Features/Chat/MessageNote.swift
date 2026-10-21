import SwiftUI

/// A note on an answer: stopped by the user, or a research step cut short (a warning).
struct MessageNote: View {
    let symbol: String
    let text: LocalizedStringKey
    let warning: Bool

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(warning ? .orange : .secondary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
