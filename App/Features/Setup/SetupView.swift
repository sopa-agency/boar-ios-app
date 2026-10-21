import SwiftUI

/// The first-run setup (android SetupScreen / SetupWizardScreen.tsx): welcome with this iPhone's numbers, the answer
/// model (recommended by RAM), the knowledge package (recommended by free space), then the downloads and the library
/// index, ending on "Open BOAR". Everything after it works offline.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let flow: SetupFlow

    var body: some View {
        NavigationStack {
            Group {
                switch flow.step {
                case .welcome: WelcomeStep(flow: flow)
                case .model: ModelStep(flow: flow)
                case .knowledge: KnowledgeStep(flow: flow)
                case .install: InstallStep(flow: flow)
                }
            }
            .navigationTitle(flow.step == .welcome ? Text(verbatim: "") : Text("Step \(flow.step.rawValue) of 4"))
            .inlineNavigationTitle()
            .toolbar {
                if flow.step == .model || flow.step == .knowledge {
                    ToolbarItem(placement: .leadingBar) {
                        Button("Back", systemImage: "chevron.backward", action: back)
                    }
                }
                if model.setupFromApp && flow.step != .install {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back to the App", action: model.finishSetup)
                    }
                }
            }
        }
        // Downloads go fastest with BOAR open: keep the screen on while setup runs.
        .onAppear { Platform.keepAwake(true) }
        .onDisappear { Platform.keepAwake(false) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { flow.onForeground() } }
    }

    private func back() {
        withAnimation { flow.back() }
    }
}
