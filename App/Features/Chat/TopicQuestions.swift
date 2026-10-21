import SwiftUI

/// An open topic on the home screen: a row back to the topics, then its questions as plain rows; a tap asks one.
struct TopicQuestions: View {
    let topic: HomeTopic
    let onAsk: (String) -> Void
    let onBack: () -> Void
    @ScaledMetric(relativeTo: .body) private var iconWidth = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onBack) {
                HStack(spacing: 16) {
                    Image(systemName: "chevron.backward")
                        .fontWeight(.semibold)
                        .frame(width: iconWidth)
                    Label {
                        Text(topic.name)
                    } icon: {
                        Image(systemName: topic.symbol)
                            .foregroundStyle(topic.color)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back to topics"))

            ForEach(topic.questions, id: \.self) { question in
                Button {
                    onAsk(question)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(width: iconWidth)
                            .accessibilityHidden(true)
                        Text(question)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.body)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Asks BOAR"))
            }
        }
    }
}
