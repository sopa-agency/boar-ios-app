import SwiftUI

/// One step of an answer in progress: a spinner and "Searching your library…" with a running timer while it runs, a
/// check and "Found 3 sources · 0.4 s" once done.
struct AnswerStepRow: View {
    let step: AnswerStep
    let active: Bool
    let stopping: Bool
    let sourceCount: Int?
    /// Deep Research: the number of sub-questions, for the finished split step.
    let laterCount: Int?
    /// When the step finished (the next step's start); nil while it runs.
    let endedAt: Date?

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 6) {
                    title
                    if active, step.kind == .subQuestion, let i = step.index, let n = step.count, n > 0 {
                        ProgressView(value: Double(i - 1), total: Double(n))
                            .accessibilityHidden(true)
                    }
                }
            } icon: {
                status
            }
            .foregroundStyle(active ? .primary : .secondary)
            Spacer(minLength: 8)
            elapsed
        }
    }

    @ViewBuilder private var status: some View {
        if active {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var elapsed: some View {
        if let endedAt {
            Text(Self.format(endedAt.timeIntervalSince(step.startedAt)))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        } else {
            TimelineView(.periodic(from: step.startedAt, by: 1)) { context in
                Text(Self.format(context.date.timeIntervalSince(step.startedAt)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 10 { return String(format: "%.1f s", s) }
        if s < 60 { return "\(Int(s)) s" }
        return "\(Int(s) / 60) min \(Int(s) % 60) s"
    }

    private var title: Text {
        if active && stopping { return Text("Stopping…") }
        switch step.kind {
        case .loading:
            return active ? Text("Loading the model…") : Text("Loaded the model")
        case .searching:
            if active { return Text("Searching your library…") }
            guard let n = sourceCount else { return Text("Searched your library") }
            return n == 0 ? Text("No matching sources") : Text("Found ^[\(n) source](inflect: true)")
        case .thinking:
            return active ? Text("Thinking…") : Text("Thought it over")
        case .splitting:
            if active { return Text("Splitting your question…") }
            if let n = laterCount { return Text("Split into ^[\(n) sub-question](inflect: true)") }
            return Text("Split your question")
        case .subQuestion:
            if active { return Text("Researching part \(step.index ?? 1) of \(step.count ?? 1)…") }
            return Text("Researched ^[\(step.count ?? 1) part](inflect: true)")
        case .writing:
            return active ? Text("Writing the answer…") : Text("Wrote the answer")
        }
    }
}
