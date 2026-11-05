import SwiftUI

/// Boar Labs (android LabsScreen.kt): a terminal-style hero, then the experiments two per row, each with what it is
/// underneath; the ones under review and the classified teasers in their own groups.
struct LabsScreen: View {
    @State private var labs = Labs.shared
    /// The tile whose note shows under the grid (a classified one that was tapped).
    @State private var note: String?
    @State private var taps: [String: Int] = [:]
    /// The tap that leaks each tile, drawn again each time Boar Labs opens, so no number gets passed around.
    @State private var revealAt: [String: Int] = [:]
    /// The tile that just leaked flashes red once.
    @State private var alert: String?
    @State private var leaks = 0

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        let visible = labs.visible
        let groups: [(LocalizedStringResource?, [any LabPlugin])] = [
            (nil, visible.filter { $0.status <= .alpha }),
            ("UNDER REVIEW", visible.filter { $0.status == .review }),
            ("IN TESTING · NO RELEASE DATE", visible.filter { $0.status == .classified }),
        ]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabsHero(open: visible.count { $0.status != .classified }, locked: visible.count { $0.status == .classified })
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if !group.1.isEmpty {
                        if let title = group.0 {
                            Text(title)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(group.1, id: \.id) { lab in tile(lab) }
                        }
                    }
                }
                if let note {
                    Text(noteText(note))
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle("Boar Labs")
        .inlineNavigationTitle()
        .navigationDestination(for: LabRoute.self) { route in
            if let lab = labs.byId(route.id) { LabPage(lab: lab) }
        }
        .sensoryFeedback(.warning, trigger: leaks)
    }

    @ViewBuilder private func tile(_ lab: any LabPlugin) -> some View {
        if labs.opened(lab) != nil {
            NavigationLink(value: LabRoute(id: lab.id)) {
                LabTile(lab: lab, flash: false)
            }
            .buttonStyle(.plain)
        } else {
            Button { tapClassified(lab) } label: {
                LabTile(lab: lab, flash: alert == lab.id)
            }
            .buttonStyle(.plain)
        }
    }

    /// Easter egg: 11 to 20 taps (a new count per tile each visit) declassify a teaser, like Android's developer options.
    /// The taps count in silence: no countdown gives it away.
    private func tapClassified(_ lab: any LabPlugin) {
        let n = (taps[lab.id] ?? 0) + 1
        taps[lab.id] = n
        let at = revealAt[lab.id] ?? Int.random(in: 11...20)
        revealAt[lab.id] = at
        if n == at && !labs.revealed(lab.id) {
            labs.reveal(lab.id)
            // A lab with code behind the teaser (the Daily Quiz) stays unlocked; its next tap opens it.
            if let classified = lab as? ClassifiedLab, classified.inner != nil { labs.unlock(lab.id) }
            alert = lab.id
            leaks += 1
        }
        note = lab.id
    }

    private func noteText(_ id: String) -> String {
        let name = labs.all.first { $0.id == id }?.title ?? id
        if labs.unlocked(id) { return String(localized: "\(name) leaked, and it's yours: tap it to open it and switch it on. Still in testing.") }
        if labs.revealed(id) { return String(localized: "\(name) leaked. Still in testing, with no release date.") }
        return String(localized: "\(name) is classified: still in testing. Check back soon.")
    }
}

/// A lab's page in the Labs stack.
struct LabRoute: Hashable {
    let id: String
}

/// The lab's console: the lines type themselves once, with a blinking cursor after.
private struct LabsHero: View {
    let open: Int
    let locked: Int
    @State private var shown = 0
    @State private var cursorOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lines: String {
        [
            String(localized: "\(open) open · \(locked) classified"),
            String(localized: "everything here runs on this \(Platform.deviceNoun), offline"),
            String(localized: "experimental: may be slow, rough, or gone tomorrow"),
        ].map { "> " + $0 }.joined(separator: "\n")
    }

    var body: some View {
        let full = lines
        // The whole console is laid out invisibly underneath, so the box has its final height before a letter is typed.
        ZStack(alignment: .topLeading) {
            console(full, cursor: false).hidden()
            console(String(full.prefix(shown)), cursor: cursorOn)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.85), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.4)))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Boar Labs. " + full.replacingOccurrences(of: "> ", with: "")))
        .task {
            if reduceMotion { shown = full.count; return }
            while shown < full.count {
                try? await Task.sleep(for: .milliseconds(14))
                shown += 1
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                cursorOn.toggle()
            }
        }
    }

    private func console(_ text: String, cursor: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "BOAR LABS")
                .font(.title2.monospaced().weight(.heavy))
                .tracking(3)
                .foregroundStyle(.green)
            Text(verbatim: text)
                .font(.caption.monospaced())
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.85))
            Text(verbatim: "█")
                .font(.caption.monospaced())
                .foregroundStyle(.green)
                .opacity(cursor ? 1 : 0)
        }
    }
}

/// One experiment's tile: its boar (a silhouette while classified), the status tag, OFF when switched off, the name and
/// what it does (blacked out while classified).
struct LabTile: View {
    let lab: any LabPlugin
    let flash: Bool
    @State private var labs = Labs.shared
    @State private var red = 0.0

    var body: some View {
        let leaked = lab.status == .classified && (labs.revealed(lab.id) || labs.unlocked(lab.id))
        let locked = lab.status == .classified && !leaked
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(locked ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.green.opacity(0.12)))
                if let art = lab.shownArt {
                    Image(art)
                        .resizable()
                        .renderingMode(locked ? .template : .original)
                        .scaledToFill()
                        .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 24 / 255))
                } else {
                    Text(verbatim: lab.emoji)
                        .font(.system(size: 56))
                        .opacity(locked ? 0.25 : 1)
                }
                if locked {
                    if lab.shownArt != nil {
                        Text(verbatim: "?").font(.largeTitle.bold()).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "lock.fill").font(.title2).foregroundStyle(.secondary)
                    }
                }
                Color.red.opacity(red)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(locked ? AnyShapeStyle(.separator) : AnyShapeStyle(Color.green.opacity(0.4))))
            .overlay(alignment: .topTrailing) {
                LabStatusTag(status: lab.status, leaked: leaked).padding(8)
            }
            .overlay(alignment: .bottom) {
                // A revealed classified lab can't be switched on, so OFF would only confuse: it has LEAKED instead.
                if !locked && lab.status != .classified && !labs.enabled(lab.id) {
                    Text("OFF")
                        .font(.system(size: 9, weight: .heavy).monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.4), in: .rect(cornerRadius: 4))
                        .padding(8)
                }
            }
            Text(verbatim: locked ? Self.redact(lab.title) : lab.title)
                .font(.headline)
                .foregroundStyle(locked ? .secondary : .primary)
                .padding(.top, 4)
            if lab.status == .review, let short = lab.reviewShort {
                Label(short, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.orange)
            }
            Text(verbatim: locked ? Self.redactAll(lab.body) : lab.body)
                .font(.footnote)
                .foregroundStyle(locked ? .tertiary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: locked ? String(localized: "Classified lab") : "\(lab.title), \(String(localized: lab.status.label))"))
        .onChange(of: flash) { _, on in
            guard on else { return }
            red = 0.7
            withAnimation(.easeOut(duration: 1)) { red = 0 }
        }
    }

    /// "Reads signs." → "▇▇▇▇▇ ▇▇▇▇▇.": every word blacked out, its length and punctuation kept, so the lines still wrap.
    static func redactAll(_ s: String) -> String {
        s.replacing(/[\p{L}\p{N}]+/) { String(repeating: "▇", count: $0.output.count) }
    }

    /// "Big Brain" → "Big ▇▇▇▇▇": the first word stays, the rest is blacked out.
    static func redact(_ s: String) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: false)
        if words.count < 2 { return String(s.prefix(1)) + String(repeating: "▇", count: max(s.count - 1, 2)) }
        return words[0] + " " + words.dropFirst().map { String(repeating: "▇", count: $0.count) }.joined(separator: " ")
    }
}

/// The status tag on a tile and a lab's page; LEAKED in alert red for a declassified teaser.
struct LabStatusTag: View {
    let status: LabStatus
    var leaked = false

    var body: some View {
        if leaked {
            Text("LEAKED")
                .font(.system(size: 10, weight: .heavy).monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.red, in: .rect(cornerRadius: 4))
        } else {
            // UNDER REVIEW reads as a warning: red and a size up from the other tags.
            let review = status == .review
            Text(status.label)
                .font(.system(size: review ? 11 : 9, weight: .heavy).monospaced())
                .foregroundStyle(color)
                .padding(.horizontal, review ? 8 : 6).padding(.vertical, review ? 3 : 2)
                // A dark base under the tint keeps the tag readable over a tile's art.
                .background(color.opacity(0.18), in: .rect(cornerRadius: 4))
                .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
        }
    }

    private var color: Color {
        switch status {
        case .live: .green
        case .beta: .cyan
        case .alpha: .orange
        case .review: .red
        case .classified: .gray
        }
    }
}
