import SwiftUI

/// A form row with a value on the right, selectable for copying (telemetry, About).
struct ValueRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(verbatim: value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
