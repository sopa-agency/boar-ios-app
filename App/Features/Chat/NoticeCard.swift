import SwiftUI

/// A notice inside the chat (an answer that failed, a model that ran out of memory): a status symbol, a short title,
/// one or two plain sentences, then the actions as small capsule buttons, the first one prominent. One shape for every
/// problem the chat reports, so people learn it once.
struct NoticeCard<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(verbatim: message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            HStack {
                actions()
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(tint.opacity(0.18))
        }
    }
}
