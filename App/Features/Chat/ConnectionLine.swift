import BoarAnswer
import SwiftUI

/// The connection on the header's second line (android `ConnectionLine`, adam's option D, Nov 12): a small dot (amber
/// online, a moon-blue ring offline) before the model's name. When BOAR opens and when the connection really changes
/// (`ConnectionPill`: once per state, after it has held), the name becomes "ONLINE" or "OFFLINE" for about 2 s, in the dot's
/// color, then turns back into the name. A tap shows the word for about 4 s; a tap while it shows opens what the connection
/// is used for (`ConnectionSheet`). Nothing changes size: one line of the same text style, cross-faded. Reduce Motion:
/// instant.
struct ConnectionLine: View {
    let online: Bool
    let model: String
    /// Opens the sheet (a tap on the word; VoiceOver's one action).
    let onDetails: () -> Void

    @State private var expanded = false
    @State private var tapped = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: LocalizedStringKey { online ? "ONLINE" : "OFFLINE" }

    var body: some View {
        HStack(spacing: 5) {
            ConnectionDot(online: online, size: 6, ring: 1.5)
            ZStack(alignment: .leading) {
                // The word and the name share one slot: whichever shows, the line keeps its size.
                Text(model)
                    .foregroundStyle(.boar(.dim))
                    .opacity(expanded ? 0 : 1)
                Text(label)
                    .fontWeight(.bold)
                    .foregroundStyle(online ? .boar(.warning) : .boar(.moon))
                    .opacity(expanded ? 1 : 0)
            }
            .boarText("mono.xs")
            .textCase(.uppercase)
            .lineLimit(1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: expanded)
        }
        .contentShape(.rect)
        .onTapGesture { if expanded { onDetails() } else { tapped += 1 } }
        .task(id: online) {
            // On open at once; a change only once it has held, so a flapping signal doesn't flash the word.
            if ConnectionPill.lastShown != nil {
                try? await Task.sleep(for: .milliseconds(ConnectionPill.settleMs))
            }
            guard !Task.isCancelled, ConnectionPill.shouldShow(online: online) else { return }
            ConnectionPill.lastShown = online
            expanded = true
            try? await Task.sleep(for: .milliseconds(ConnectionPill.showMs))
            if !Task.isCancelled { expanded = false }
        }
        .task(id: tapped) {
            guard tapped > 0 else { return }
            expanded = true
            try? await Task.sleep(for: .milliseconds(ConnectionPill.tapShowMs))
            if !Task.isCancelled { expanded = false }
        }
        // One element that says the state and the model, with one action that opens the sheet (android: TalkBack).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(online ? String(localized: "ONLINE") : String(localized: "OFFLINE")). \(model)"))
        .accessibilityHint(Text("Double tap for details"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onDetails)
    }
}

/// The connection's dot: filled amber online, a moon-blue ring offline (android's 6 dp dot and 8 dp sheet dot).
struct ConnectionDot: View {
    let online: Bool
    let size: CGFloat
    let ring: CGFloat

    var body: some View {
        Group {
            if online {
                Circle().fill(.boar(.warning))
            } else {
                Circle().strokeBorder(.boar(.moon).opacity(0.55), lineWidth: ring)
            }
        }
        .frame(width: size, height: size)
    }
}
