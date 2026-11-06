import SwiftUI

/// The finished install: what is now on the iPhone.
struct SetupDoneSection: View {
    let flow: SetupFlow

    var body: some View {
        SetupHeader(title: "Ready", message: "Everything runs offline from now on.")
        Section {
            if let m = flow.chosenModel {
                LabeledContent("Answer Model", value: m.friendlyName)
            }
            LabeledContent("Library", value: flow.package.title)
            LabeledContent("Articles") {
                Text("^[\(flow.indexTotal) article](inflect: true)")
                    .monospacedDigit()
            }
        }
        .boarRowBackground()
    }
}
