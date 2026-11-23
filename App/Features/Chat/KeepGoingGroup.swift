import BoarAnswer
import BoarCore
import BoarRouting
import SwiftUI

/// "Keep going" (android KeepGoingGroup, adam Nov 13-14; t9 0235): a small label and up to three faint bubbles under the
/// latest answer, on the user's side: the user's bubble shape, a dashed border, a light fill. The step first (its verb, then
/// the ladder with the rungs done filled), then follow-up questions. A tap asks; holding a follow-up puts it in the input.
struct KeepGoingGroup: View {
    let last: ChatItem
    let question: String
    let onStep: (KeepGoing.Step) -> Void
    let onAsk: (String) -> Void
    let onFill: (String) -> Void
    @Environment(\.palette) private var palette

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                      bottomTrailingRadius: 8, topTrailingRadius: 20)

    private var speaker: Labs.Speaker? { last.receipt?.tool.flatMap { Labs.shared.speaker(tool: $0) } }

    /// What the answer was, and so what is offered (KeepGoing.of).
    private var next: KeepGoing.Next {
        let r = last.receipt
        var follow: [String] = []
        // Off until adam reads the table (KeepGoing.followUpsOn); only the packs' cited articles, never the user's files.
        if KeepGoing.followUpsOn {
            let pt = QueryContext.isPortugueseQuestion(question)
            follow = FollowUps.pick(question, last.sources.enumerated().map { i, s in
                FollowUps.Source(title: s.title, body: s.body, cited: last.text.contains("[\(i + 1)]"), fromPack: s.source?.contains(" — ") == true)
            }, pt: pt)
        }
        return KeepGoing.of(KeepGoing.Answer(
            broken: last.failure != nil || last.stopped || last.timedOut,
            instant: r?.tool != nil && r?.tokens == 0, canBypass: speaker?.canBypass == true,
            style: r?.style, deepResearch: r?.path == "deep", cut: last.cutAt != nil, keptShort: r?.styleNote != nil,
            hasSources: !last.sources.isEmpty), followUps: follow)
    }

    var body: some View {
        let next = next
        if next.step != nil || !next.followUps.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text("Keep going")
                    .boarText("mono.xs")
                    .foregroundStyle(Color(palette.textDim))
                if let step = next.step { stepBubble(step) }
                ForEach(next.followUps, id: \.self) { q in followUpBubble(q) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Keep going: what to ask next"))
        }
    }

    private func stepBubble(_ step: KeepGoing.Step) -> some View {
        let name = speaker?.title ?? ""
        let verb: String = switch step {
        case .deeper: String(localized: "Go deeper")
        case .continue: String(localized: "Continue")
        case .research: String(localized: "Research this")
        case .ask: String(localized: "keepgoing.ask", defaultValue: "Ask BOAR")
        }
        let rungs: [String] = step == .ask ? [name, String(localized: "BOAR")]
            : [String(localized: "Quick"), String(localized: "Detailed"), String(localized: "Research")]
        let done = KeepGoing.rungsDone(step)
        let spoken: String = switch step {
        case .deeper: String(localized: "Go deeper: ask the same question again, in Detailed.")
        case .continue: String(localized: "Continue: BOAR goes on from its last answer.")
        case .research: String(localized: "Research this: ask the same question again, with Deep Research.")
        case .ask: String(localized: "Ask BOAR: the model answers this question instead of \(name).")
        }
        return Button { onStep(step) } label: {
            bubble {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verb)
                        .boarText("ui.body")
                        .fontWeight(.bold)
                        .underline(pattern: .dot)
                        .foregroundStyle(Color(palette.textMuted))
                    if KeepGoing.showsLadder(step) {
                        Text(rungs.enumerated().map { (i, n) in (i < done ? "● " : "○ ") + n }.joined(separator: "  ›  "))
                            .boarText("mono.xs")
                            .foregroundStyle(Color(palette.textDim))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spoken))
    }

    private func followUpBubble(_ q: String) -> some View {
        bubble {
            Text(q)
                .boarText("ui.body")
                .foregroundStyle(Color(palette.textSecondary))
        }
        .onTapGesture { onAsk(q) }
        .onLongPressGesture { onFill(q) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ask: \(q)"))
        .accessibilityAddTraits(.isButton)
    }

    /// The faint bubble: the user's shape, a light fill, a dashed border, a 44 pt target.
    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44, alignment: .leading)
            .frame(maxWidth: 320, alignment: .leading)
            .background(Color(palette.bgCardHover).opacity(0.35), in: Self.shape)
            .overlay { Self.shape.stroke(Color(palette.borderDefault), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
            .contentShape(Self.shape)
    }
}
