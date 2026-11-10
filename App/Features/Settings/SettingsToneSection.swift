import BoarAnswer
import BoarCore
import BoarModels
import SwiftUI

/// Answers: the answer style (with its own prompt for Custom) and Deep Research.
struct SettingsToneSection: View {
    let services: BoarServices
    let bridge: SettingsBridge

    var body: some View {
        let personalities = services.personalities
        let id = bridge.read { $0.personalityId } ?? personalities.defaultId
        Section {
            DrillDownPicker(
                title: "Answer Style",
                selection: bridge.binding({ $0.personalityId ?? personalities.defaultId }, { $0.personalityId = $1 }),
                options: personalities.personalities.map { p in
                    DrillDownOption(value: p.id, title: Text(verbatim: p.displayLabel), symbol: p.symbol,
                                    detail: Text(verbatim: p.displayDescription))
                }
            ) {
                SettingsLabel("Answer Style", symbol: Symbols.tone)
            } current: {
                Text(verbatim: personalities.get(id).displayLabel)
            }
            if id == "custom" {
                TextField("Write your own instructions…", text: bridge.binding({ $0.customSystemPrompt ?? "" }, { $0.customSystemPrompt = $1 }), axis: .vertical)
                    .lineLimit(3...8)
            }
            Toggle(isOn: bridge.binding({ $0.deepResearchMode }, { $0.deepResearchMode = $1 })) {
                SettingsLabel("Deep Research", symbol: Symbols.deepResearch)
            }
        } header: {
            BoarHeader {
                Text("Answers")
            }
        } footer: {
            BoarFooter {
                VStack(alignment: .leading) {
                    Text("\(personalities.get(id).displayDescription) Deep Research splits your question into parts. Slower.")
                    if let missing = missingSearchModel {
                        Label("The search model (\(missing)) isn't on this \(Platform.deviceNoun), so answers can't use your library. Run Setup Again in Advanced.", icon: Symbols.caution)
                            .foregroundStyle(.boar(.warning))
                    }
                }
            }
        }
    }

    /// The embedding model's friendly name when it is missing.
    private var missingSearchModel: String? {
        guard let emb = services.catalog.models.first(where: { $0.kind == .embedding }), !services.isPresent(emb) else { return nil }
        return emb.friendlyName
    }
}
