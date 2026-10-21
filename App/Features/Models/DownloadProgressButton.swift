import SwiftUI

/// A download's trailing accessory: a determinate ring with a stop square inside; tapping it cancels.
struct DownloadProgressButton: View {
    let fraction: Double
    let onCancel: () -> Void

    var body: some View {
        Button(action: onCancel) {
            DownloadRing(fraction: fraction, showsStop: true)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Cancel Download")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// The determinate ring itself (setup shows it without the cancel).
struct DownloadRing: View {
    let fraction: Double
    var showsStop = false

    var body: some View {
        // A circular ProgressView is always indeterminate on iOS; the capacity gauge draws the determinate ring.
        Gauge(value: min(max(fraction, 0), 1)) {
            EmptyView()
        } currentValueLabel: {
            if showsStop {
                Image(systemName: Symbols.stop)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.accentColor)
        .scaleEffect(0.55)
        .frame(width: 32, height: 32)
    }
}
