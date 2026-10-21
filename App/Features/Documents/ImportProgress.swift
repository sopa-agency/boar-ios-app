import SwiftUI

/// The import's current stage in one progress view, with an icon-only cancel.
struct ImportProgress: View {
    let stage: DocumentsController.Stage
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Group {
                switch stage {
                case .reading:
                    ProgressView { Text("Reading files…") }
                case .recognizing(let done, let total):
                    ProgressView(value: Double(done), total: Double(max(total, 1))) { Text("Recognizing text…") }
                case .chunking:
                    ProgressView { Text("Preparing for search…") }
                case .embedding(let done, let total):
                    ProgressView(value: Double(done), total: Double(max(total, 1))) {
                        Text("Preparing for search… \(done) of \(total)")
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel Import", systemImage: "xmark.circle.fill", action: onCancel)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
