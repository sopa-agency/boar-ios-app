import BoarAnswer
import SwiftUI

/// The models to test, each checked on or off.
struct EvalConfigsSection: View {
    let controller: EvaluationController

    var body: some View {
        Section {
            if let configs = controller.configs {
                if configs.isEmpty {
                    ContentUnavailableView("No Answer Models", systemImage: Symbols.model, description: Text("Download an answer model in Models first."))
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
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if on {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .tint(.primary)
                    .disabled(controller.running)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Models to Test")
        } footer: {
            Text("BOAR \(controller.appVersion). Each model answers every question with the default answer style; one model is in memory at a time.")
        }
    }
}
