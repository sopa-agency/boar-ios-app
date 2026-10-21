import BoarAnswer
import BoarModels
import SwiftUI

/// The answer (ChatScreen.tsx assistantBubble): while it works, the steps it is going through; once done, what it searched
/// (the numbered sources, collapsed). Then the reasoning (collapsed), the text, a failure with Try Again, and the footer.
struct AnswerView: View {
    let message: ChatItem
    let chat: ChatController
    let onOpenSource: (ChatSource) -> Void
    @Environment(AppModel.self) private var model

    private var streaming: Bool { chat.answeringId == message.id }
    private var split: SplitThinking { AnswerText.splitThinking(message.text) }
    /// Invented citations (past the source count) are cleaned once the answer ends.
    private var shown: String {
        streaming ? split.answer : AnswerText.splitInlineBullets(AnswerText.cleanCitations(split.answer, sourceCount: message.sources.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.text == AesTextCipher.locked {
                Label("Locked Chat", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                if streaming {
                    AnswerStatus(message: message, stopping: chat.stopping)
                } else if message.failure == nil {
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
                if message.stopped { MessageNote(symbol: Symbols.stop, text: "Stopped", warning: false) }
                if message.timedOut { MessageNote(symbol: Symbols.caution, text: "A research step took too long and was cut short", warning: true) }
                if !message.text.isEmpty && !streaming {
                    AnswerFooter(message: message, chat: chat, shown: shown)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A citation "[n]" in this answer opens this answer's source n.
        .environment(\.openURL, OpenURLAction(handler: openCitation))
    }

    private func failureRow(_ failure: String) -> some View {
        NoticeCard(symbol: message.failureNoModel ? Symbols.model : "exclamationmark.triangle.fill", tint: .red,
                   title: message.failureNoModel ? "No Answer Model" : "BOAR Couldn't Finish This Answer", message: failure) {
            if message.failureNoModel {
                Button("Open Models", systemImage: Symbols.model, action: openModels)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Try Again", systemImage: Symbols.retry, action: retry)
                    .buttonStyle(.borderedProminent)
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

    private func openCitation(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "boar-source" else { return .systemAction }
        if let n = Int(url.host() ?? ""), n >= 1, n <= message.sources.count { onOpenSource(message.sources[n - 1]) }
        return .handled
    }
}
