import BoarCore
import SwiftUI

/// One topic on the home screen, a plain row above the question field. A tap shows its questions in place of the topics.
struct TopicRow: View {
    let topic: HomeTopic
    let onOpen: () -> Void
    /// The icon column, so the names line up at every text size.
    @ScaledMetric(relativeTo: .body) private var iconWidth = 26
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                Image(systemName: topic.symbol)
                    .foregroundStyle(topic.color)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(topic.name)
                    .foregroundStyle(Color(palette.textPrimary))
            }
            .boarText("ui.body")
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Color(palette.bgCard), in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows questions to ask"))
    }
}
