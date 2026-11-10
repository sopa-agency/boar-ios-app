import BoarAnswer
import SwiftUI

/// The models to test, each checked on or off.
struct EvalConfigsSection: View {
    let controller: EvaluationController

    var body: some View {
        Section {
            if let configs = controller.configs {
                if configs.isEmpty {
                    ContentUnavailableView("No Answer Models", icon: Symbols.model, description: Text("Download an answer model in Models first."))
                }
                ForEach(configs, id: \.id) { cfg in
                    let on = controller.selected.contains(cfg.id)
                    Button {
                        controller.toggle(cfg.id)
                    } label: {
                        HStack {
                            let name = controller.name(cfg)
                            VStack(alignment: .leading) {
                                Text(verbatim: name.plain)
                                if let model = name.model {
                                    Text(verbatim: model)
                                        .font(.boar("ui.subtext"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if on {
                                Image(icon: Symbols.active)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.boar(.accent))
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                        .foregroundStyle(.boar(.primary), .boar(.secondary))
                    }
                    .disabled(controller.running)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            } else {
                ProgressView()
            }
        } header: {
            BoarHeader {
                Text("Models to Test")
            }
        } footer: {
            BoarFooter {
                Text("BOAR \(controller.appVersion). Each model answers every question with the default answer style; one model is in memory at a time.")
            }
        }
    }
}
