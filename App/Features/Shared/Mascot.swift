import SwiftUI

extension EnvironmentValues {
    /// The Boar Avatar in the mascot's place (android `LocalTruffle`): the equipped one while Boarverse is on, nil for
    /// BOAR's own. RootView provides it.
    @Entry var truffle: String?
}

/// BOAR's mascot (android R.drawable.mascot), where Android shows it: the chat's empty state and header, the name on
/// each answer, and "Ask BOAR instead"; the equipped Boar Avatar instead while Boarverse is on (android
/// `TruffleVault.avatar`). Decorative: the name next to it says who it is.
struct Mascot: View {
    let size: CGFloat
    /// A circle, as the chat header crops it; otherwise the whole picture. An avatar is square art: a rounded square
    /// keeps its ears and tusks (android Header: 10 dp on 42).
    var circle = false
    @Environment(\.truffle) private var truffle

    var body: some View {
        picture
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(shape)
            .accessibilityHidden(true)
    }

    private var picture: Image { TruffleArt.image(truffle, or: "Brand/mascot") }

    private var shape: AnyShape {
        guard circle else { return AnyShape(.rect) }
        return truffle == nil ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: size * 10 / 42))
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
    @Environment(\.truffle) private var truffle

    var body: some View {
        VStack(spacing: 16) {
            TruffleArt.image(truffle, or: "Brand/mascot")
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 24))
                .accessibilityHidden(true)
            // White in every theme: the veil is black, and Paper's heading color (black) would vanish on it.
            Text(verbatim: AvatarCopy.name(truffle))
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
