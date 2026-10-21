import BoarModels
import SwiftUI

/// The user's question, like Messages: tint background, white text, trailing. A sealed chat shows "Locked Chat".
struct UserBubble: View {
    let text: String
    let onReuse: (String) -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            if text == AesTextCipher.locked {
                Label("Locked Chat", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(text)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.tint, in: .rect(cornerRadius: 20))
                    .contextMenu {
                        Button("Ask Again", systemImage: Symbols.retry, action: reuse)
                        Button("Copy", systemImage: "doc.on.doc", action: copy)
                    }
                    .accessibilityLabel(Text("You: \(text)"))
            }
        }
    }

    private func reuse() {
        onReuse(text)
    }

    private func copy() {
        Platform.copy(text)
    }
}
