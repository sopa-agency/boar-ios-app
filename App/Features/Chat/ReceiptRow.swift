import SwiftUI

/// One measured step of an answer.
struct ReceiptRow: View {
    let label: LocalizedStringKey
    let symbol: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(verbatim: value).monospacedDigit()
        } label: {
            Label(label, systemImage: symbol)
        }
    }
}
