import SwiftUI

/// Run or stop the benchmark, with where the results were saved.
struct EvalRunSection: View {
    let controller: EvaluationController
    let chatBusy: Bool

    private var canRun: Bool { !controller.running && !chatBusy && !controller.chosen.isEmpty && controller.configs != nil }

    var body: some View {
        Section {
            if controller.running {
                Button(controller.stopping ? "Stopping…" : "Stop", icon: Symbols.stop, action: controller.stop)
                    .disabled(controller.stopping)
            } else {
                Button("Run Benchmark", systemImage: "play.fill", action: controller.run)
                    .disabled(!canRun)
            }
            if let id = controller.requestId, controller.running {
                Label("Started from a connected computer (request \(id)).", systemImage: "desktopcomputer")
            }
            if let error = controller.error {
                Label {
                    Text("The benchmark failed: \(error)")
                } icon: {
                    Image(icon: Symbols.error).foregroundStyle(.boar(.danger))
                }
            }
            if let path = controller.savedPath {
                Label {
                    Text(controller.stopped ? "Stopped early. Partial results saved to \(path)." : "Saved to \(path).")
                        .font(.boar("ui.subtext"))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(icon: controller.stopped ? Symbols.caution : Symbols.active)
                        .foregroundStyle(.boar(controller.stopped ? .warning : .success))
                }
            }
        } footer: {
            BoarFooter {
                let n = controller.queries.count
                let c = controller.chosen.count
                if chatBusy {
                    Text("Wait for the current answer to finish before running the benchmark.")
                } else {
                    Text("^[\(n) question](inflect: true) × ^[\(c) model](inflect: true) = ^[\(n * c) answer](inflect: true). \(Self.awakeNote)")
                }
            }
        }
    }
}

extension EvalRunSection {
    /// What keeps running during the benchmark: the iPhone's screen, the Mac itself.
    static var awakeNote: String {
        #if os(macOS)
        String(localized: "Your Mac stays awake while it runs.")
        #else
        String(localized: "The screen stays on while it runs.")
        #endif
    }
}
