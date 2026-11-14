import SwiftUI

/// An address to type or paste (android AboutScreen `Link`), never opened from here: a tap or the context menu copies
/// `copy` (the text itself by default), and the row says Copied for a moment.
struct AddressRow: View {
    let text: String
    let copy: String
    @State private var copied = false

    init(_ text: String, copy: String? = nil) {
        self.text = text
        self.copy = copy ?? text
    }

    var body: some View {
        Button(action: copyAddress) {
            HStack {
                Text(verbatim: text)
                    .boarText("mono.sm")
                    .foregroundStyle(.boar(.link))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .boarText("mono.xs")
                        .foregroundStyle(.boar(.success))
                } else {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.boar(.dim))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint("Copies the address")
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: copyAddress)
        }
    }

    private func copyAddress() {
        Platform.copy(copy)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}
