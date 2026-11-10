import BoarModels
import SwiftUI

/// One answer model to pick: the selection circle on the left edge, then the shared model row (name with the
/// recommended or fit badge, what it's for, the real model and its size).
struct ModelChoiceRow: View {
    let model: CatalogAsset
    let flow: SetupFlow

    private var selected: Bool { flow.chosenId == model.id }
    private var fit: Compatibility { flow.fit(model) }

    var body: some View {
        Button(action: choose) {
            HStack {
                Image(icon: .pack(selected ? .radioOn : .radioOff))
                    .font(.title2)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.boar(.dim)))
                    .accessibilityHidden(true)
                ModelRowContent(asset: model, fit: fit, recommended: flow.recommendedId == model.id)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(fit == .red && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose() {
        flow.choose(model.id)
    }
}
