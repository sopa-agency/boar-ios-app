import BoarAnswer
import BoarCore
import BoarModels
import SwiftUI

/// The user's question, trailing, on Android's user bubble (bgCardHover, the bottom-trailing corner tucked in). A sealed
/// chat shows "Locked Chat".
struct UserBubble: View {
    let text: String
    /// The Keep going step that sent it: the bubble shows its verb, everything else (copy, ask again, VoiceOver) keeps the question.
    var step: KeepGoing.Step?
    let onReuse: (String) -> Void
    @Environment(\.palette) private var palette

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                      bottomTrailingRadius: 8, topTrailingRadius: 20)

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            if text == AesTextCipher.locked {
                Label("Locked Chat", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(shownText)
                    .boarText("ui.bodyLg")
                    .foregroundStyle(Color(palette.textPrimary))
                    .textSelection(.enabled)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(palette.bgCardHover), in: Self.shape)
                    .contextMenu {
                        Button("Ask Again", icon: Symbols.retry, action: reuse)
                        Button("Copy", systemImage: "doc.on.doc", action: copy)
                    }
                    .accessibilityLabel(accessibilityText)
            }
        }
    }

    /// The question, or a Keep going step's verb (the text stays the question).
    private var shownText: String {
        switch step {
        case .deeper: String(localized: "Go deeper")
        case .research: String(localized: "Research this")
        case .ask: String(localized: "Ask BOAR: \(text)")
        case .continue, nil: text
        }
    }

    /// VoiceOver reads the question, after the step's verb when one shows. Two `Text`s, so each key stays localized (a
    /// ternary of two literals can be typed as `String` and skip the catalog).
    private var accessibilityText: Text {
        shownText == text ? Text("You: \(text)") : Text("You: \(shownText). \(text)")
    }

    private func reuse() {
        onReuse(text)
    }

    private func copy() {
        Platform.copy(text)
    }
}
