import SwiftUI

/// The screen behind a sidebar entry in the Library section.
struct DestinationScreen: View {
    @Environment(AppModel.self) private var model
    let screen: AppScreen

    var body: some View {
        switch screen {
        case .settings:
            if let services = model.services { SettingsScreen(services: services) }
        case .models:
            if let models = model.models { ModelsScreen(controller: models) }
        case .documents:
            if let documents = model.documents, let models = model.models { DocumentsScreen(documents: documents, models: models) }
        case .evaluation:
            if let evaluation = model.evaluation { EvaluationScreen(controller: evaluation, chatBusy: model.chat?.isAnswering ?? false) }
        case .about:
            AboutScreen()
        }
    }
}
