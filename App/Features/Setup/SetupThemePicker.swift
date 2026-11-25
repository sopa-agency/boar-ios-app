import SwiftUI

/// Setup's theme chips (android ThemePicker): the same choices and the same write as Settings → Display.
struct SetupThemePicker: View {
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
struct FlowChips: Layout {
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
