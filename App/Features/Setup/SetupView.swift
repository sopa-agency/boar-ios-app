import BoarCore
import SwiftUI

/// The first-run setup (android SetupScreen / SetupWizardScreen.tsx): welcome with this iPhone's numbers, the answer
/// model (recommended by RAM), the knowledge package (recommended by free space), then the downloads and the library
/// index. While they run, step 4 is the guide (SetupGuideView), whose last page opens BOAR; the download's details show
/// on request. Everything after it works offline.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette
    let flow: SetupFlow

    var body: some View {
        NavigationStack {
            Group {
                switch flow.step {
                case .welcome: WelcomeStep(flow: flow)
                case .model: ModelStep(flow: flow)
                case .knowledge: KnowledgeStep(flow: flow)
                case .install:
                    if flow.details { InstallStep(flow: flow) } else { SetupGuideView(flow: flow) }
                }
            }
            // Android's setup background (bgTerminal), under the bars too.
            .background(Color(palette.bgTerminal).ignoresSafeArea())
            // The guide counts its own pages: no step in the bar over them.
            .navigationTitle(flow.step == .welcome || (flow.step == .install && !flow.details) ? Text(verbatim: "") : Text("Step \(flow.step.rawValue) of 4"))
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
