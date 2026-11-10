import BoarCore
import BoarModels
import SwiftUI

/// A model's row, the same in setup and in Models, in the type of Android's catalog card (the name in titleSm, subtext,
/// the size in mono): a tinted icon tile, the plain name with at most one small badge (Recommended, or the fit verdict
/// when it is tight), what the model is for, and one quiet line with the real model and its size. Three short lines,
/// each with one job, so a list of models reads at a glance.
struct ModelRowContent<Status: View>: View {
    let asset: CatalogAsset
    let fit: Compatibility
    var recommended = false
    /// Replaces the purpose line while something is happening (download progress, an error, loading).
    @ViewBuilder var status: () -> Status

    private var dimmed: Bool { fit == .red }

    var body: some View {
        HStack(spacing: 12) {
            ModelIconTile(symbol: asset.symbol, dimmed: dimmed)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: asset.friendlyName)
                        .font(.boar("ui.titleSm"))
                        .foregroundStyle(.boar(dimmed ? .muted : .heading))
                    badge
                }
                if Status.self == EmptyView.self {
                    Text(verbatim: asset.plainPurpose)
                        .font(.boar("ui.subtext"))
                        .foregroundStyle(.boar(.secondary))
                } else {
                    status()
                        .font(.boar("ui.subtext"))
                }
                Text(verbatim: meta)
                    .boarText("mono.xs")
                    .foregroundStyle(.boar(.dim))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    /// "Qwen2.5-1.5B · 986 MB".
    private var meta: String {
        let size = FeatureFormat.megabytes(asset.sizeBytes)
        guard let name = asset.modelName else { return size }
        return "\(name) · \(size)"
    }

    @ViewBuilder private var badge: some View {
        if fit == .yellow || fit == .red, let label = fit.plainShortLabel {
            ModelBadge(text: label, tone: fit.tone, dot: true)
        } else if recommended {
            ModelBadge.recommended
        }
    }
}

extension ModelRowContent where Status == EmptyView {
    init(asset: CatalogAsset, fit: Compatibility, recommended: Bool = false) {
        self.init(asset: asset, fit: fit, recommended: recommended) { EmptyView() }
    }
}

/// A small badge next to a model's name ("Recommended", "May be slow"), as Android's StatusBadge and RamBadge draw it:
/// bold mono text on the tone's subtle wash inside its border, with a status dot for a verdict.
struct ModelBadge: View {
    enum Tone: Sendable {
        /// Emerald: recommended, in use.
        case accent
        /// Amber: may be slow.
        case warning
        /// Crimson: too big.
        case danger
        /// Cyan: informational.
        case link
    }

    let text: LocalizedStringKey
    let tone: Tone
    var dot = false
    @Environment(\.palette) private var palette

    private var colors: (fg: ARGB, bg: ARGB, border: ARGB) {
        switch tone {
        case .accent: (palette.textAccentEmerald, palette.emeraldBgSubtle, palette.emeraldBorder)
        case .warning: (palette.textAccentAmber, palette.amberBgSubtle, palette.amberBorder)
        case .danger: (palette.crimson400, palette.crimsonBgSubtle, palette.crimsonBorder)
        case .link: (palette.textAccentCyan, palette.cyanBgSubtle, palette.cyanBorder)
        }
    }

    /// Setup's pick, as Android's setup Badge (SetupScreen.kt): micro capitals in textInverse on solid emerald500.
    static var recommended: some View { SolidBadge(text: "Recommended") }

    var body: some View {
        let c = colors
        let shape = RoundedRectangle(cornerRadius: Radii.sm)
        HStack(spacing: 5) {
            if dot {
                Circle()
                    .fill(Color(c.fg))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.boar("mono.xs").bold())
        }
        .foregroundStyle(Color(c.fg))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color(c.bg), in: shape)
        .overlay(shape.strokeBorder(Color(c.border), lineWidth: 1))
        .lineLimit(1)
    }
}

/// A solid accent badge: micro capitals in textInverse on emerald500 (Android's setup Badge).
private struct SolidBadge: View {
    let text: LocalizedStringKey
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.boar("ui.micro").bold())
            .foregroundStyle(Color(palette.textInverse))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(palette.emerald500), in: RoundedRectangle(cornerRadius: Radii.sm))
            .lineLimit(1)
    }
}

/// A model's symbol on a rounded tile in the accent's subtle wash and border (Android's emerald accents on a card); a
/// quiet tile when the model can't run here.
struct ModelIconTile: View {
    let symbol: AppIcon
    var dimmed = false
    @ScaledMetric(relativeTo: .title3) private var side = 44
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.27)
        Image(icon: symbol)
            .font(.title3)
            .foregroundStyle(Color(dimmed ? palette.textDim : palette.textAccentEmerald))
            .frame(width: side, height: side)
            .background(Color(dimmed ? palette.bgSubtle : palette.emeraldBgSubtle), in: shape)
            .overlay(shape.strokeBorder(Color(dimmed ? palette.borderSubtle : palette.emeraldBorder), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
