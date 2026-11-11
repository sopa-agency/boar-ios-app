import BoarAnswer
import BoarCore
import SwiftUI

// The tour's previews (android ui/tour/TourPreviews.kt): small, still pictures of the app drawn with the theme's colors,
// so the theme card repaints them live. They copy the look of the chat, Knowledge, Models and Settings rows; nothing
// here reacts to a tap. Each one is labelled EXAMPLE: its numbers are made up. VoiceOver reads each as one picture.

/// The example under a card, or nothing for a card without one.
struct TourPreview: View {
    let card: TourCard

    var body: some View {
        switch card {
        case .theme: TourFrame { TourUserBubble(); TourAnswer(withSources: false) }
        case .styles: TourFrame { TourStyles() }
        case .deep: TourFrame { TourDeepResearch() }
        case .sources: TourFrame { TourAnswer(withSources: true) }
        case .knowledge: TourFrame { TourDocument() }
        case .models: TourFrame { TourModel() }
        case .adaptive: TourFrame { TourAdaptive() }
        case .welcome, .lock, .labs, .end: EmptyView()
        }
    }
}

/// The EXAMPLE box every preview sits in: the chat's background, a live dot and the label.
private struct TourFrame<Content: View>: View {
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

private struct TourUserBubble: View {
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

/// BOAR's answer as the chat draws it: the mascot and name, the text, then (with `withSources`) its sources, and the
/// receipt.
private struct TourAnswer: View {
    let withSources: Bool
    @Environment(\.palette) private var palette

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 6,
                                                      bottomTrailingRadius: 16, topTrailingRadius: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BoarSpeakerLabel(researched: false)
            Text("Boil it for at least one minute [1], then let it cool covered [2].")
                .boarText("ui.body")
                .foregroundStyle(.boar(.primary))
            if withSources {
                VStack(alignment: .leading, spacing: 4) {
                    source(1, "Water purification")
                    source(2, "Boiling")
                }
                .padding(.top, 2)
            }
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

    private func source(_ n: Int, _ title: String) -> some View {
        Label {
            Text(verbatim: "\(title) · Wikipedia").lineLimit(1)
        } icon: {
            Image(systemName: "\(n).circle")
        }
        .boarText("ui.subtext")
        .foregroundStyle(.boar(.secondary))
    }
}

/// The chat's style button, then the answer styles as its sheet lists them, Thorough & Detailed picked.
private struct TourStyles: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    private let picked = "detailed"

    private var styles: [Personality] {
        let all = model.services?.personalities ?? (try? Personalities.bundled())
        return (all?.personalities ?? []).filter { $0.id != "custom" }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(icon: styles.first { $0.id == picked }?.symbol ?? Symbols.tone)
                .frame(width: 40, height: 40)
                .background(Color(palette.bgInput), in: .circle)
                .overlay(Circle().strokeBorder(Color(palette.borderDefault)))
                .foregroundStyle(.boar(.primary))
            Text("The style button, next to where you type")
                .boarText("ui.subtext")
                .foregroundStyle(.boar(.muted))
        }
        ForEach(styles, id: \.id) { style in
            let on = style.id == picked
            HStack(spacing: 10) {
                Image(icon: style.symbol)
                    .foregroundStyle(.boar(on ? .success : .primary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: style.displayLabel)
                        .boarText("ui.body")
                        .foregroundStyle(.boar(on ? .success : .primary))
                    Text(verbatim: style.displayDescription)
                        .boarText("ui.subtext")
                        .foregroundStyle(.boar(.muted))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if on {
                    Image(icon: Symbols.active).foregroundStyle(.boar(.success))
                }
            }
            .padding(10)
            .background(Color(on ? palette.emeraldBgSubtle : palette.bgCard), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(on ? palette.emeraldBorder : palette.borderSubtle)))
        }
    }
}

/// Deep Research on, as the chat shows it: the lit 🔬 button, and the input bar's brighter border.
private struct TourDeepResearch: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(icon: Symbols.deepResearch)
                .frame(width: 34, height: 34)
                .background(Color(palette.frontierBadgeBg), in: .circle)
                .overlay(Circle().strokeBorder(Color(palette.frontierBadgeBorder)))
            Text("ON · deeper, slower answers")
                .boarText("ui.subtext")
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color(palette.frontierText))
        Text("Ask with Deep Research")
            .boarText("ui.body")
            .foregroundStyle(Color(palette.frontierText))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(palette.bgInput), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(palette.frontierBadgeBorder), lineWidth: 1.5))
    }
}

/// An imported document, as Knowledge lists it.
private struct TourDocument: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: "📄").font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("field-manual.pdf")
                    .boarText("ui.body")
                    .foregroundStyle(.boar(.primary))
                Text("42 pages · in Personal Files")
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.muted))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(palette.bgCard), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(palette.borderSubtle)))
        TourChip(text: Text("Ask with 🗂️ Personal Files"), fg: palette.textAccentEmerald, bg: palette.emeraldBgSubtle,
                 border: palette.emeraldBorder)
    }
}

/// A Models card: the default model, its size, how it fits this device, the setup badge.
private struct TourModel: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: "Qwen3 4B")
                    .boarText("ui.title")
                    .foregroundStyle(.boar(.heading))
                Spacer(minLength: 0)
                TourChip(text: Text("Recommended"), fg: palette.textInverse, bg: palette.emerald500, border: palette.emerald500)
            }
            Text(verbatim: "LLM · 2.5 GB · Apache-2.0")
                .boarText("mono.xs")
                .foregroundStyle(.boar(.dim))
            TourChip(text: Text(verbatim: "●  " + String(localized: "Fits this \(Platform.deviceNoun)")), fg: palette.textAccentEmerald,
                     bg: palette.emeraldBgSubtle, border: palette.emeraldBorder)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(palette.bgCard), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(palette.borderSubtle)))
    }
}

/// The Adaptive Routing switch as Settings → Advanced shows it, off.
private struct TourAdaptive: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Toggle(isOn: .constant(false)) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Adaptive Routing")
                    .boarText("ui.body")
                    .foregroundStyle(.boar(.heading))
                Text("Picks a model per question from the ones installed.")
                    .boarText("ui.subtext")
                    .foregroundStyle(.boar(.muted))
            }
        }
        .allowsHitTesting(false)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(palette.bgCard), in: .rect(cornerRadius: 10))
    }
}

private struct TourChip: View {
    let text: Text
    let fg: ARGB
    let bg: ARGB
    let border: ARGB

    var body: some View {
        text
            .boarText("mono.xs")
            .fontWeight(.bold)
            .foregroundStyle(Color(fg))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(bg), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(border)))
    }
}
