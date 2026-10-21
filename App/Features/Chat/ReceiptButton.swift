import SwiftUI

/// The answer's receipt with technical details on: "21.8 s · 9.1 tok/s", tapped open for the measured details.
struct ReceiptButton: View {
    let receipt: Receipt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Receipt.seconds(receipt.totalMs)) · \(Receipt.rate(receipt.tokPerSec)) tok/s")
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityLabel(Text("Answered in \(Receipt.seconds(receipt.totalMs)) at \(Receipt.rate(receipt.tokPerSec)) tokens per second"))
        .accessibilityHint("Shows performance details")
    }
}
