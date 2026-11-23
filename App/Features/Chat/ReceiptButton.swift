import SwiftUI

/// The answer's receipt, at the start of the footer (android `ReceiptShort` / `ReceiptToggle`, adam Nov 14): "21.8 s ·
/// 9.1 tok/s", for everyone; an instant answer (a plugin's, no model) only its time, "instant" being the Speed row of the
/// opened details. With technical details on it is tapped open for the measured details.
struct ReceiptButton: View {
    let receipt: Receipt
    /// Technical details on: a button that opens the details; off: nothing to open.
    let opens: Bool
    let action: () -> Void

    private var short: String {
        receipt.instant ? Receipt.seconds(receipt.totalMs) : String(localized: "\(Receipt.seconds(receipt.totalMs)) · \(Receipt.rate(receipt.tokPerSec)) tok/s")
    }

    var body: some View {
        if opens {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityHint("Shows performance details")
        } else {
            label
        }
    }

    private var label: some View {
        Text(verbatim: short)
            .boarText("mono.xs")
            .monospacedDigit()
            .foregroundStyle(.boar(.muted))
            // Two lines with Large text rather than losing "tok/s" off the end (android maxLines = 2).
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .accessibilityLabel(Text(spoken))
    }

    private var spoken: String {
        receipt.instant ? String(localized: "Answered in \(Receipt.seconds(receipt.totalMs))")
            : String(localized: "Answered in \(Receipt.seconds(receipt.totalMs)) at \(Receipt.rate(receipt.tokPerSec)) tokens per second")
    }
}
