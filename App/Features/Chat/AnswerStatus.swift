import SwiftUI

/// What the answer is doing, as a checklist while it works: the steps already done with a check and how long each
/// took, the current one with a spinner and a live timer. It stays while the text streams in below it.
struct AnswerStatus: View {
    let message: ChatItem
    let stopping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(message.steps.enumerated()), id: \.offset) { i, step in
                AnswerStepRow(step: step, active: i == message.steps.count - 1, stopping: stopping,
                              sourceCount: message.sourceCount, laterCount: laterCount(after: i), endedAt: endedAt(i))
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    /// Deep Research: how many sub-questions the split produced (known from the next step).
    private func laterCount(after i: Int) -> Int? {
        message.steps.dropFirst(i + 1).first { $0.kind == .subQuestion }?.count
    }

    /// A finished step ends when the next one starts.
    private func endedAt(_ i: Int) -> Date? {
        i + 1 < message.steps.count ? message.steps[i + 1].startedAt : nil
    }
}
