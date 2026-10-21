import SwiftUI

/// One topic on the home screen, a plain row above the question field. A tap shows its questions in place of the topics.
struct TopicRow: View {
    let topic: HomeTopic
    let onOpen: () -> Void
    /// The icon column, so the names line up at every text size.
    @ScaledMetric(relativeTo: .body) private var iconWidth = 26

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                Image(systemName: topic.symbol)
                    .foregroundStyle(topic.color)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(topic.name)
                    .foregroundStyle(.primary)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows questions to ask"))
    }
}
