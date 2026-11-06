import SwiftUI

/// Step 3: the knowledge package, recommended by free space.
struct KnowledgeStep: View {
    let flow: SetupFlow

    private var plan: PackagePlan? { flow.plans.first { $0.package == flow.package } }
    private var bytes: Int64 { plan?.downloadBytes ?? 0 }

    var body: some View {
        List {
            SetupHeader(title: "Library",
                        message: "What BOAR can read to answer you. It downloads once, together with the answer model; then BOAR works offline.")
            Section {
                ForEach(flow.plans) { p in
                    PackageRow(plan: p, flow: flow)
                }
                .boarRowBackground()
            } footer: {
                Text("Sizes are the whole download, answer model included.")
            }
        }
        .groupedListStyle()
        .boarListBackground()
        .readableWidth()
        // The header is the first row: no extra list margin between it and the navigation bar.
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            SetupBottomButton(title: bytes > 0 ? "Download \(FeatureFormat.megabytes(bytes))" : "Continue",
                              enabled: (plan?.shortfallBytes ?? 0) == 0, action: install)
        }
    }

    private func install() {
        withAnimation { flow.install() }
    }
}
