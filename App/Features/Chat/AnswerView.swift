import BoarAnswer
import BoarCore
import BoarModels
import SwiftUI

/// The answer (ChatScreen.tsx assistantBubble): while it works, the steps it is going through; once done, what it searched
/// (the numbered sources, collapsed). Then the reasoning (collapsed), the text, a failure with Try Again, and the footer.
struct AnswerView: View {
    let message: ChatItem
    let chat: ChatController
    let onOpenSource: (ChatSource) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 8,
                                                      bottomTrailingRadius: 20, topTrailingRadius: 20)

    private var streaming: Bool { chat.answeringId == message.id }
    private var split: SplitThinking { AnswerText.splitThinking(message.text) }
    /// Invented citations (past the source count) are cleaned once the answer ends.
    private var shown: String {
        streaming ? split.answer : AnswerText.splitInlineBullets(AnswerText.cleanCitations(split.answer, sourceCount: message.sources.count))
    }

    /// A Labs plugin's instant answer speaks as that plugin: its art and name, not BOAR's.
    private var speaker: Labs.Speaker? { message.receipt?.tool.flatMap { Labs.shared.speaker(tool: $0) } }

    private var researched: Bool { message.receipt?.path == "deep" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let speaker, !streaming {
                LabSpeakerLabel(speaker: speaker)
            } else {
                BoarSpeakerLabel(researched: researched)
            }
            if message.text == AesTextCipher.locked {
                Label("Locked Chat", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                // Boar Staged answers: what the sources say comes first, above the answer's text, and takes the place of the
                // sources list under it (one design, adam Nov 12).
                if let staged = message.staged {
                    StagedCard(staged: staged, streaming: streaming, written: !message.text.isEmpty, answerId: message.id, onOpen: openQuote)
                }
                if streaming {
                    // Once the staged answer has started, the card's step line says what's happening.
                    if message.staged == nil || message.text.isEmpty {
                        AnswerStatus(message: message, stopping: chat.stopping)
                    }
                } else if message.failure == nil, StagedChat.listsSources(staged: message.staged) {
                    SourcesList(message: message, technicalDetails: chat.technicalDetails, onOpen: onOpenSource)
                }
                if split.thinking != nil || split.thinkingInProgress {
                    ThinkingDisclosure(thinking: split.thinking ?? "", active: streaming && split.thinkingInProgress,
                                       unfinished: !streaming && split.thinkingInProgress, seconds: message.thinkingSeconds)
                }
                if !shown.isEmpty {
                    MarkdownText(text: shown, sourceCount: message.sources.count, answerId: message.id)
                }
                if let failure = message.failure {
                    failureRow(failure)
                }
                // Answered in another style than the one picked (a health question under Detailed): said once, under it.
                if !streaming, let note = message.receipt?.styleNote {
                    switch note {
                    case "health": MessageNote(symbol: Symbols.shortAnswer, text: "Short answer: health questions are kept brief.", warning: false)
                    case "seed": MessageNote(symbol: Symbols.shortAnswer, text: "Short answer: seed-phrase questions are kept brief, for your safety.", warning: false)
                    default: EmptyView()
                    }
                }
                // Every number written is in a source (or is not), once the staged answer's check has run.
                if !streaming, !message.text.isEmpty, !message.sources.isEmpty, let staged = message.staged {
                    StagedCheck(staged: staged)
                }
                // Nothing in the library backs it: said, not left to guess (t9 0226 point 4).
                if !streaming, NoSource.shows(searched: message.receipt?.retrievalMs != nil, sources: message.sources.count, instant: message.receipt?.tool != nil,
                                              question: chat.question(for: message.id) ?? "", answer: message.text, style: message.receipt?.style) {
                    MessageNote(symbol: Symbols.shortAnswer, text: "No source in this \(Platform.deviceNoun)'s library covers this; the answer is from the model alone.", warning: false)
                }
                if message.stopped { MessageNote(symbol: Symbols.stop, text: "Stopped", warning: false) }
                if message.timedOut { MessageNote(symbol: Symbols.caution, text: "A research step took too long and was cut short", warning: true) }
                // The plugin answered without the model: the same question, plugins skipped (never the CO safety answer).
                // BOAR's mascot on it: a way out of the plugin's answer, not one of its controls (android ChatScreen).
                if !streaming, speaker?.canBypass == true {
                    Button {
                        chat.askModel(message.id)
                    } label: {
                        Label {
                            Text("Ask BOAR instead")
                        } icon: {
                            Mascot(size: 20)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                    }
                    // In the accent, like Android's ActionButton (Try again, Allow more).
                    .buttonStyle(.boarAction)
                    .disabled(chat.isAnswering)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // The cut is a note; the way to run it again with more tokens is its own button on the next line, so the
                // two never squeeze into one row (android ChatScreen).
                if let limit = message.cutAt {
                    VStack(alignment: .leading, spacing: 6) {
                        MessageNote(symbol: Symbols.cutAtLimit, text: "Stopped at the \(String(limit))-token limit", warning: false)
                        if let next = message.nextLimit, !chat.isAnswering {
                            Button("Allow \(String(next)) and redo", icon: Symbols.retry) {
                                chat.redo(message.id, limit: next)
                            }
                            .buttonStyle(.boarAction)
                        }
                    }
                }
                if !message.text.isEmpty && !streaming {
                    AnswerFooter(message: message, chat: chat, shown: shown)
                }
            }
        }
        .foregroundStyle(Color(palette.textPrimary))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(palette.bgSurface), in: Self.shape)
        // A Deep Research answer keeps its mark in the history: 1.5 pt in the mode's color (android Bubble).
        .overlay {
            Self.shape.strokeBorder(Color(researched ? palette.frontierBadgeBorder : palette.borderDefault), lineWidth: researched ? 1.5 : 1)
        }
        // A citation "[n]" in this answer opens this answer's source n.
        .environment(\.openURL, OpenURLAction(handler: openCitation))
    }

    private func failureRow(_ failure: String) -> some View {
        NoticeCard(symbol: message.failureNoModel ? Symbols.model : "exclamationmark.triangle.fill", tint: .red,
                   title: message.failureNoModel ? "No Answer Model" : "BOAR Couldn't Finish This Answer", message: failure) {
            if message.failureNoModel {
                Button("Open Models", icon: Symbols.model, action: openModels)
                    .buttonStyle(.boarProminent)
            } else {
                Button("Try Again", icon: Symbols.retry, action: retry)
                    .buttonStyle(.boarProminent)
                    .disabled(chat.isAnswering)
                Button("Choose a Model", action: openModels)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func retry() {
        chat.retry(message.id)
    }

    private func openModels() {
        model.selection = .screen(.models)
    }

    /// A tap on a quote opens its source: the passage it came from, and the article at that passage.
    private func openQuote(_ fact: KeyFactView) {
        let number = message.sources.first { $0.docId != nil && $0.docId == fact.docId && $0.title == fact.title }?.number
            ?? message.sources.first { $0.title == fact.title }?.number ?? 1
        onOpenSource(ChatSource(number: number, title: fact.title, source: fact.source, relevance: fact.relevance,
                                similarity: fact.similarity, docId: fact.docId, body: fact.passage))
    }

    private func openCitation(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "boar-source" else { return .systemAction }
        if let n = Int(url.host() ?? ""), n >= 1, n <= message.sources.count { onOpenSource(message.sources[n - 1]) }
        return .handled
    }
}
