import BoarAnswer
import SwiftUI

// Setup's theme page preview (android ui/setup/ThemePreview.kt, from the retired tour): a small, still picture of the
// chat drawn with the theme's colors, so picking a theme repaints it live. Labelled EXAMPLE: nothing here reacts to a tap,
// and its numbers are made up. VoiceOver reads it as one picture.

/// The chat as the chosen theme draws it.
struct ThemePreview: View {
    var body: some View {
        PreviewFrame { PreviewUserBubble(); PreviewAnswer() }
    }
}

/// The EXAMPLE box every preview sits in: the chat's background, a live dot and the label.
private struct PreviewFrame<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color(palette.emerald500)).frame(width: 6, height: 6)
                Text("Example")
                    .textCase(.uppercase)
                    .boarText("ui.micro")
                    .fontWeight(.bold)
                    .foregroundStyle(.boar(.muted))
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(palette.bgTerminal), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(palette.borderDefault)))
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewUserBubble: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("You")
                    .boarText("mono.xs")
                    .fontWeight(.semibold)
                    .foregroundStyle(.boar(.link))
                Text("How do I make water safe to drink?")
                    .boarText("ui.body")
                    .foregroundStyle(.boar(.primary))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(palette.bgCardHover),
                        in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 6,
                                                   topTrailingRadius: 16))
        }
    }
}

/// BOAR's answer as the chat draws it: the mascot and name, the text, and the receipt.
private struct PreviewAnswer: View {
    @Environment(\.palette) private var palette

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 6,
                                                      bottomTrailingRadius: 16, topTrailingRadius: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BoarSpeakerLabel(researched: false)
            Text("Boil it for at least one minute [1], then let it cool covered [2].")
                .boarText("ui.body")
                .foregroundStyle(.boar(.primary))
            Rectangle().fill(Color(palette.borderSubtle)).frame(height: 0.5)
            Text(verbatim: "12 s · 11 tok/s · Qwen3 4B")
                .boarText("mono.xs")
                .foregroundStyle(.boar(.muted))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(palette.bgSurface), in: Self.shape)
        .overlay(Self.shape.strokeBorder(Color(palette.borderDefault)))
    }
}
