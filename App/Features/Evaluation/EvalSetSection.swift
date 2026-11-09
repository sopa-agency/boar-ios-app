import BoarAnswer
import SwiftUI

/// Which questions to run: a quick slice of the research bench, the whole public bench, or the app's original set.
struct EvalSetSection: View {
    @Bindable var controller: EvaluationController

    var body: some View {
        Section {
            Picker("Question Set", selection: $controller.setKind) {
                ForEach(controller.sets) { set in
                    Text(set.kind.title)
                        .tag(set.kind)
                }
            }
            .disabled(controller.running)
        } header: {
            BoarHeader {
                Text("Questions")
            }
        } footer: {
            BoarFooter {
                if let set = controller.questionSet {
                    Text(set.kind.detail(count: set.queries.count, checked: set.checkedOnDevice))
                }
            }
        }
    }
}

extension EvalQuestionSet.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .quick: "Quick Check"
        case .bench: "Research Bench v0.1"
        case .smoke: "App Smoke Test"
        }
    }

    func detail(count: Int, checked: Int) -> LocalizedStringKey {
        switch self {
        case .quick:
            "^[\(count) question](inflect: true) from the public research bench, one or two per topic. Every answer is checked on this \(Platform.deviceNoun)."
        case .bench:
            "All \(count) public questions of the BOAR research bench. \(checked) are checked on this \(Platform.deviceNoun); venue, first-aid and open-ended answers are judged on a computer."
        case .smoke:
            "The app's original \(count) questions, for comparing with earlier and Android runs. No fact check."
        }
    }
}
