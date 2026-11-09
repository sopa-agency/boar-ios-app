import SwiftUI

/// One library package to pick, in the same shape as the model rows: the selection circle, an icon tile, the name with
/// one badge (Recommended, or Too big when it doesn't fit the free space), what it adds, and its size.
struct PackageRow: View {
    let plan: PackagePlan
    let flow: SetupFlow

    private var selected: Bool { flow.package == plan.package }

    private var size: String {
        if plan.downloadBytes == 0 { return String(localized: "Already on this \(Platform.deviceNoun)") }
        if plan.downloadBytes == plan.installedBytes { return FeatureFormat.megabytes(plan.downloadBytes) }
        return String(localized: "\(FeatureFormat.megabytes(plan.downloadBytes)) to download")
    }

    var body: some View {
        Button(action: choose) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.boar(.dim)))
                    .accessibilityHidden(true)
                HStack(spacing: 12) {
                    ModelIconTile(symbol: plan.package == .essential ? Symbols.pack : Symbols.library)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(plan.package.title)
                                .font(.boar("ui.titleSm"))
                                .foregroundStyle(.boar(.heading))
                            if plan.shortfallBytes > 0 {
                                ModelBadge(text: "Too big", tone: .danger, dot: true)
                            } else if flow.recommendedPackage == plan.package {
                                ModelBadge.recommended
                            }
                        }
                        Text(verbatim: plan.package.body)
                            .font(.boar("ui.subtext"))
                            .foregroundStyle(.boar(.secondary))
                        Text(verbatim: plan.shortfallBytes > 0
                             ? String(localized: "\(size) · needs \(FeatureFormat.megabytes(plan.shortfallBytes)) more free space")
                             : size)
                            .boarText("mono.sm")
                            .foregroundStyle(.boar(plan.shortfallBytes > 0 ? .danger : .secondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose() {
        flow.choosePackage(plan.package)
    }
}
