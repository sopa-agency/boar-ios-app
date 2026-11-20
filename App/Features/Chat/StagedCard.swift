import BoarAnswer
import BoarCore
import SwiftUI

/// Boar Staged answers, over the answer's text (android `StagedCard`): the sentences from the sources that answer (quotes,
/// never BOAR's own words; a tap shows the passage and opens the article), the step running now, what the research step
/// added. While the answer is written the quotes are open; a tap on the heading folds them. The rest of the sources are
/// one tap away behind "+N sources".
struct StagedCard: View {
    let staged: StagedView
    let streaming: Bool
    /// The answer's text has started.
    let written: Bool
    let answerId: String
    let onOpen: (KeyFactView) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        // No sources, no block (adam, Nov 12): nothing to quote and no step line, so no empty area and no gap.
        if staged.hasContent(streaming: streaming, written: written) {
            let factsOpen = ChatFolds.shared.binding("\(answerId)/staged", default: true)
            let moreOpen = ChatFolds.shared.binding("\(answerId)/staged/more", default: false)
            VStack(alignment: .leading, spacing: 6) {
                if !staged.keyFacts.isEmpty {
                    Button { factsOpen.wrappedValue.toggle() } label: {
                        Text(heading(open: factsOpen.wrappedValue))
                            .font(.boar("mono.xs").bold())
                            .foregroundStyle(Color(palette.textDim))
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(factsOpen.wrappedValue ? "Folds the quotes" : "Shows the quotes"))
                    if factsOpen.wrappedValue {
                        ForEach(Array(staged.keyFacts.enumerated()), id: \.offset) { _, fact in quote(fact) }
                        // The rest of the sources, one tap away (adam, Nov 10: 2 or 3 quotes are good as they are).
                        if !staged.more.isEmpty { moreSources(moreOpen) }
                        Text("Quoted from the sources, not BOAR's answer. Tap one for its passage.")
                            .font(.boar("ui.subtext")).italic()
                            .foregroundStyle(Color(palette.textDim))
                    }
                } else if !staged.more.isEmpty {
                    // No sentence matched the question: the sources are still one tap away, never an empty block (validator S-2).
                    moreSources(moreOpen)
                }
                // The step line once the answer has started; before its first word the chat's wait line says what's happening.
                if streaming && written, let step = staged.step {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini).tint(Color(palette.textAccentEmerald))
                        Text(Self.stepLine(step)).font(.boar("ui.subtext")).foregroundStyle(Color(palette.textMuted))
                    }
                    .accessibilityElement(children: .combine)
                }
                if staged.added > 0 {
                    Text("+\(staged.added) sources found while answering")
                        .font(.boar("ui.subtext")).foregroundStyle(Color(palette.textSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heading(open: Bool) -> String {
        String(localized: "FROM THE SOURCES (\(staged.keyFacts.count))") + (open ? "" : " ›")
    }

    private func moreSources(_ open: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.wrappedValue.toggle() } label: {
                Text(open.wrappedValue ? String(localized: "Fewer sources ‹") : String(localized: "+\(staged.more.count) sources") + " ›")
                    .font(.boar("mono.xs").bold())
                    .foregroundStyle(Color(palette.textAccentCyan))
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            if open.wrappedValue {
                ForEach(Array(staged.more.enumerated()), id: \.offset) { _, fact in quote(fact) }
            }
        }
    }

    /// One quote: the sentence, its source, and (a health answer) its passage, never a sentence alone out of context.
    private func quote(_ fact: KeyFactView) -> some View {
        Button { onOpen(fact) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "“\(fact.sentence)”").font(.boar("ui.body")).foregroundStyle(Color(palette.textPrimary))
                Text(verbatim: "— \(fact.title)").font(.boar("ui.subtext")).foregroundStyle(Color(palette.textSecondary))
                if staged.withPassages {
                    Text(fact.passage).font(.boar("ui.subtext")).foregroundStyle(Color(palette.textMuted))
                }
            }
            .multilineTextAlignment(.leading)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(palette.bgCard), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows the passage BOAR read"))
    }

    private static func stepLine(_ step: StagedStep) -> String {
        switch step {
        case .sources: String(localized: "Searching the library…")
        case .intro: String(localized: "Writing a short answer…")
        case .research: String(localized: "Looking for more sources…")
        case .details: String(localized: "Adding the details…")
        case .check: String(localized: "Checking the numbers…")
        }
    }
}

/// Under the answer: the number check, once it's done (android `StagedCheck`).
struct StagedCheck: View {
    let staged: StagedView
    @Environment(\.palette) private var palette

    var body: some View {
        if let unsupported = staged.unsupported {
            Group {
                if unsupported.isEmpty {
                    Text(verbatim: "✓ ") + Text("Every number in this answer is in its sources.")
                } else {
                    Text(verbatim: "⚠ ") + Text("Not found in the sources: \(unsupported.joined(separator: ", ")). Check them before you rely on them.")
                }
            }
            .font(.boar("ui.subtext"))
            .foregroundStyle(Color(unsupported.isEmpty ? palette.textAccentEmerald : palette.textAccentAmber))
        }
    }
}
