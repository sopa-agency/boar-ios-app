import SwiftUI

/// BOAR's mascot (android R.drawable.mascot), where Android shows it: the chat's empty state and header, the name on
/// each answer, and "Ask BOAR instead". Decorative: the name next to it says who it is.
struct Mascot: View {
    let size: CGFloat
    /// A circle, as the chat header crops it; otherwise the whole picture.
    var circle = false

    var body: some View {
        Image(decorative: "Brand/mascot")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(circle ? AnyShape(.circle) : AnyShape(.rect))
    }
}

/// Who wrote an answer, above it (android Bubble's speaker row): BOAR's mascot and name, or "BOAR · 🔬 DEEP RESEARCH"
/// for a Deep Research answer, in mono.xs emerald.
struct BoarSpeakerLabel: View {
    let researched: Bool
    @ScaledMetric(relativeTo: .caption) private var side = 20

    var body: some View {
        HStack(spacing: 6) {
            Mascot(size: side)
                .clipShape(.rect(cornerRadius: 4))
            // The same in Portuguese (android values-pt).
            Text(verbatim: researched ? "BOAR · 🔬 DEEP RESEARCH" : "BOAR")
                .speakerStyle()
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The speaker row's name: mono.xs, semibold, a little tracking, emerald (android Bubble).
    func speakerStyle() -> some View {
        boarText("mono.xs")
            .fontWeight(.semibold)
            .tracking(0.5)
            .foregroundStyle(.boar(.success))
    }
}

#if os(iOS)
/// The chat's title in the navigation bar with BOAR's mascot before it (android Header: the round avatar, then the
/// name): the chat's title, and under it the model answering. A tap on the mascot shows it full screen.
struct ChatTitle: View {
    let title: String
    let subtitle: String
    let onMascot: () -> Void
    @ScaledMetric(relativeTo: .headline) private var side = 30

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMascot) {
                Mascot(size: side, circle: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "BOAR"))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundStyle(.boar(.heading))
                // The model, as Android's header writes it: mono.xs, upper case, textDim.
                Text(verbatim: subtitle)
                    .boarText("mono.xs")
                    .textCase(.uppercase)
                    .foregroundStyle(.boar(.dim))
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The header's mascot full screen (android AvatarFull): the picture and its name on a dark veil; a tap anywhere
/// closes it.
struct MascotFullView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(decorative: "Brand/mascot")
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 24))
            // White in every theme: the veil is black, and Paper's heading color (black) would vanish on it.
            Text(verbatim: "BOAR")
                .boarText("ui.titleLg")
                .foregroundStyle(.white)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture(perform: onClose)
        .presentationBackground(Color.black.opacity(0.85))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Close"))
    }
}
#endif
