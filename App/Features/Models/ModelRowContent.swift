import BoarModels
import SwiftUI

/// A model's row, the same in setup and in Models: a tinted icon tile, the plain name with at most one small badge
/// (Recommended, or the fit verdict when it is tight), what the model is for, and one quiet line with the real model
/// and its size. Three short lines, each with one job, so a list of models reads at a glance.
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
                        .font(.headline)
                        .foregroundStyle(dimmed ? .secondary : .primary)
                    badge
                }
                if Status.self == EmptyView.self {
                    Text(verbatim: asset.plainPurpose)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    status()
                        .font(.subheadline)
                }
                Text(verbatim: meta)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
            ModelBadge(text: label, color: fit.color)
        } else if recommended {
            ModelBadge(text: "Recommended", color: .accentColor)
        }
    }
}

extension ModelRowContent where Status == EmptyView {
    init(asset: CatalogAsset, fit: Compatibility, recommended: Bool = false) {
        self.init(asset: asset, fit: fit, recommended: recommended) { EmptyView() }
    }
}

/// A small tinted capsule next to a model's name ("Recommended", "May be slow").
struct ModelBadge: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: .capsule)
            .lineLimit(1)
    }
}

/// A model's symbol on a tinted rounded tile (grey when the model can't run here).
struct ModelIconTile: View {
    let symbol: String
    var dimmed = false
    @ScaledMetric(relativeTo: .title3) private var side = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .frame(width: side, height: side)
            .background(dimmed ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.tint.quaternary), in: .rect(cornerRadius: side * 0.27))
            .accessibilityHidden(true)
    }
}
