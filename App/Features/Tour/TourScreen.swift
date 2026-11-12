import BoarCore
import SwiftUI

/// BOAR's tour (android ui/tour/TourScreen.kt), full screen, one card at a time, opened from Settings → See the Tour. It
/// shows and changes nothing, except the theme card, which applies a theme live, as Settings → Display does.
///
/// Not ported: the setup download bar and the "BOAR is ready" banner on top. Android's setup shows its own guide
/// (SetupGuide.kt) while it downloads and only Settings opens the tour, always without a download under it.
struct TourScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    private let cards = TourCard.cards(experimental: LabsBuild.experimental)

    init(index: Int = 0) {
        _index = State(initialValue: index)
    }

    private var position: Int { min(max(index, 0), cards.count - 1) }
    private var card: TourCard { cards[position] }
    private var last: Bool { position == cards.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                TourCardView(card: card)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readableWidth()
            }
            // A new card starts at its top.
            .id(card)
            .background(Color(palette.bgTerminal))
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(Text("BOAR tour"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Escape closes the sheet on the Mac, too.
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .macSheetSize(width: 560, height: 720)
        // VoiceOver stays on Next or Back otherwise, and never hears that the card changed.
        .onChange(of: position) {
            AccessibilityNotification.ScreenChanged(nil).post()
        }
    }

    /// Back (from the second card on), the dots, and Next, or Done on the last card.
    private var controls: some View {
        HStack(spacing: 12) {
            Group {
                if position > 0 {
                    Button(action: back) {
                        Label("Back", icon: .pack(.arrowBack))
                            .foregroundStyle(.boar(.muted))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(cards.indices, id: \.self) { n in
                    Circle()
                        .fill(Color(n == position ? palette.emerald500 : palette.bgSubtle))
                        .frame(width: 6, height: 6)
                }
            }
            .fixedSize()
            .accessibilityElement()
            .accessibilityLabel(Text("Card \(position + 1) of \(cards.count)"))
            Button(action: forward) {
                HStack(spacing: 6) {
                    Text(last ? Self.done : Self.next)
                    if !last { Image(icon: .pack(.arrowForward)).accessibilityHidden(true) }
                }
                .boarText("ui.titleSm")
                .foregroundStyle(Color(palette.textInverse))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .tint(Color(palette.emerald500))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(Color(palette.bgTerminal))
    }

    // Their own keys: the tour's PT is Android's "Próximo" and "Pronto", not the app's "Próxima" and "OK".
    private static let next = LocalizedStringResource("tour.next", defaultValue: "Next", comment: "Tour button; PT is masculine (o cartão)")
    private static let done = LocalizedStringResource("tour.done", defaultValue: "Done", comment: "Tour button on the last card")

    private func back() {
        index = position - 1
    }

    private func forward() {
        if last { dismiss() } else { index = position + 1 }
    }
}

/// One card: its picture, title and text, the example under it, and where to find it.
private struct TourCardView: View {
    let card: TourCard
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var artSide = 96
    @ScaledMetric(relativeTo: .largeTitle) private var iconSide = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            art
            Text(card.title)
                .boarText("ui.headline")
                .boarDisplayLines()
                .foregroundStyle(.boar(.heading))
                .accessibilityAddTraits(.isHeader)
            Text(card.text)
                .boarText("ui.body")
                .foregroundStyle(.boar(.primary))
            if card == .theme {
                // Below the chips, so a tap repaints the example right under the finger.
                TourThemePicker()
            }
            TourPreview(card: card)
            if let place = card.place {
                Text(place)
                    .boarText("ui.subtext")
                    .foregroundStyle(.boar(.link))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(palette.cyanBgSubtle), in: .rect(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder private var art: some View {
        switch card.art {
        case .avatar?: picture("Brand/boar")
        case .mascot?: picture("Brand/mascot")
        case .icon(let icon)?:
            Image(icon: icon)
                .font(.system(size: iconSide))
                .foregroundStyle(.boar(.heading))
                .accessibilityHidden(true)
        case nil: EmptyView()
        }
    }

    private func picture(_ name: String) -> some View {
        Image(decorative: name)
            .resizable()
            .scaledToFill()
            .frame(width: artSide, height: artSide)
            .clipShape(.rect(cornerRadius: 20))
    }
}

/// The theme card's chips (android ThemePicker): the same choices and the same write as Settings → Display.
private struct TourThemePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        FlowChips {
            ForEach(model.themeChoices) { choice in
                let on = model.theme == choice
                Button {
                    model.setTheme(choice)
                } label: {
                    choice.title
                        .boarText("ui.body")
                        .foregroundStyle(Color(on ? palette.textAccentEmerald : palette.textPrimary))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(on ? palette.emeraldBgSubtle : palette.bgCard), in: .capsule)
                        .overlay(Capsule().strokeBorder(Color(on ? palette.emeraldBorder : palette.borderDefault)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: model.theme) { _, _ in model.services?.settings.hapticsEnabled ?? false }
    }
}

/// Chips that wrap onto the next line when they don't fit (Compose's FlowRow).
private struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = chipSize(of: subviews[i], width: bounds.width)
                // Centred in the row, as Compose's FlowRow does with chips of different heights.
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = chipSize(of: subviews[i], width: width)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }

    /// A chip's size, at most the row's width: at large text sizes a wide chip wraps its text instead of running off.
    private func chipSize(of subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > width, width.isFinite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

extension View {
    /// The tour over everything: full screen on iPhone, a sheet on the Mac.
    func tourCover(isPresented: Binding<Bool>, index: Int = 0) -> some View {
        modifier(TourCover(isPresented: isPresented, index: index))
    }
}

/// Presents the tour with the theme applied to its own presentation: its theme card changes the theme while it's open,
/// and the cover's bars and system appearance must follow, not only the palette it inherits.
private struct TourCover: ViewModifier {
    @Binding var isPresented: Bool
    let index: Int
    @Environment(AppModel.self) private var model
    /// The presenter's appearance: under System, the device's.
    @Environment(\.colorScheme) private var presenterScheme

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $isPresented) { tour }
        #else
        content.fullScreenCover(isPresented: $isPresented) { tour }
        #endif
    }

    private var tour: some View {
        TourScreen(index: index)
            .boarTheme(model.theme)
            // Outside boarTheme, so this one is what the presentation reads. System has no scheme of its own (nil), and
            // a presentation keeps the last one it was given: Campfire, then System, stayed dark. Name the presenter's.
            .preferredColorScheme(model.theme.colorScheme ?? presenterScheme)
    }
}
