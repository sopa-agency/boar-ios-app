import BoarModels
import SwiftUI

/// Models and Knowledge as Settings shows them (android SettingsScreen ModelsSection and KnowledgeSection,
/// CorpusSettingsTab.tsx): what answers now, the knowledge packs and Personal Files on this device, and the way to each
/// screen.
struct SettingsLibrarySection: View {
    @Environment(AppModel.self) private var model
    let services: BoarServices

    var body: some View {
        let packs = services.catalog.corpusCatalog.filter(services.isPresent).map(\.friendlyName)
        let collections = model.documents?.collections.count ?? 0
        Section {
            LabeledContent {
                Text(model.chat?.modelName ?? services.answerModel()?.friendlyName ?? String(localized: "None"))
            } label: {
                SettingsLabel("Answering With", symbol: Symbols.model)
            }
            Button {
                model.selection = .screen(.models)
            } label: {
                SettingsLabel("Open Models", symbol: Symbols.model)
            }
            LabeledContent {
                Text(packs.isEmpty ? String(localized: "None") : packs.formatted(.list(type: .and)))
                    .multilineTextAlignment(.trailing)
            } label: {
                SettingsLabel("BOAR Knowledge", symbol: Symbols.library)
            }
            LabeledContent {
                Text("^[\(collections) collection](inflect: true)")
            } label: {
                SettingsLabel("Personal Files", symbol: Symbols.collection)
            }
            Button {
                model.selection = .screen(.documents)
            } label: {
                SettingsLabel("Open Knowledge", symbol: Symbols.library)
            }
        } header: {
            BoarHeader {
                Text("Models and Knowledge")
            }
        } footer: {
            BoarFooter {
                Text("What BOAR answers with and searches, all on this \(Platform.deviceNoun).")
            }
        }
        .task { await model.documents?.refresh() }
    }
}
