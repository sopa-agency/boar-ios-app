import BoarCore
import SwiftUI

/// The questions waiting their turn, above the input (android `QueueStrip`): a note with the merge and clear icons, then
/// one row each, "⏳ 1", the question and ✕. They run one at a time after the answer in progress.
struct QueueStrip: View {
    let chat: ChatController
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("They run one at a time, after this answer.")
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(Color(palette.textMuted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Icons: merge the waiting questions into one (two or more), and clear the queue.
                if chat.queued.count >= 2 {
                    Button(action: chat.mergeQueue) {
                        Text(verbatim: "⇉")
                            .font(.boar("ui.title"))
                            .foregroundStyle(Color(palette.textAccentCyan))
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Merge into one question")
                    #if os(macOS)
                    .help("Merge into one question")
                    #endif
                }
                Button(action: chat.clearQueue) {
                    Label("Clear queue", icon: Symbols.delete)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color(palette.textMuted))
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help("Clear queue")
                #endif
            }
            ForEach(Array(chat.queued.enumerated()), id: \.element.id) { index, prompt in
                HStack(spacing: 8) {
                    // Just the hourglass and the place in line: "⏳ 1".
                    Text(verbatim: "⏳ \(index + 1)")
                        .font(.boar("mono.xs").bold())
                        .foregroundStyle(Color(palette.textAccentEmerald))
                    Text(prompt.text)
                        .font(.boar("ui.caption"))
                        .foregroundStyle(Color(palette.textSecondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { chat.removeQueued(prompt.id) } label: {
                        Text(verbatim: "✕")
                            .font(.boar("mono.xs"))
                            .foregroundStyle(Color(palette.textDim))
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(palette.bgCardElevated))
        .accessibilityElement(children: .contain)
    }
}
