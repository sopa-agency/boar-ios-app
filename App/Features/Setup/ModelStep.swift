import BoarModels
import SwiftUI

/// Step 2: the answer model, recommended by this iPhone's memory. The two tiers first; the other models wait in a
/// collapsed group.
struct ModelStep: View {
    let flow: SetupFlow
    @State private var showOthers = false

    private var tiers: [CatalogAsset] { flow.models.filter { $0.answerTier != nil } }
    private var others: [CatalogAsset] { flow.models.filter { $0.answerTier == nil } }

    private var compactRecommended: Bool {
        guard let rec = flow.recommendedId.flatMap({ id in flow.models.first { $0.id == id } }) else { return false }
        return flow.isCompact(rec)
    }

    var body: some View {
        List {
            SetupHeader(title: "Answer Model",
                        message: "BOAR writes its answers with this model, right on your \(Platform.deviceNoun). You can change it later in Models.")
            Section {
                ForEach(tiers) { m in
                    ModelChoiceRow(model: m, flow: flow)
                }
                .boarRowBackground()
            } footer: {
                if compactRecommended {
                    Text("This \(Platform.deviceNoun) has \(flow.totalRamBytes.formatted(.byteCount(style: .memory))) of memory, so Fast is recommended.")
                }
            }
            if !others.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showOthers) {
                        ForEach(others) { m in
                            ModelChoiceRow(model: m, flow: flow)
                        }
                    } label: {
                        LabeledContent {
                            Text("\(others.count) more")
                        } label: {
                            Text("Other Models")
                            Text("Larger and alternative models")
                        }
                    }
                    .boarRowBackground()
                }
            }
        }
        .groupedListStyle()
        .boarListBackground()
        .readableWidth()
        // The header is the first row: no extra list margin between it and the navigation bar.
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            SetupBottomButton(title: "Continue", enabled: flow.chosenId != nil, action: next)
        }
        .onAppear {
            // A model chosen earlier from the other models stays in view.
            if let id = flow.chosenId, others.contains(where: { $0.id == id }) { showOthers = true }
        }
    }

    private func next() {
        withAnimation { flow.next() }
    }
}
