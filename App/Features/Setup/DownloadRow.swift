import BoarModels
import SwiftUI

/// One file being downloaded during setup: its friendly name, one secondary line, and one trailing accessory
/// (the progress ring, the done checkmark or the failure mark).
struct DownloadRow: View {
    let progress: AssetProgress

    private var line: String {
        if progress.error != nil { return String(localized: "Download failed") }
        if progress.done { return progress.asset.plainPurpose }
        if progress.verifying { return String(localized: "Checking…") }
        if progress.bytesDone > 0 {
            return String(localized: "\(FeatureFormat.megabytes(progress.bytesDone)) of \(FeatureFormat.megabytes(progress.asset.sizeBytes))")
        }
        return String(localized: "Waiting · \(FeatureFormat.megabytes(progress.asset.sizeBytes))")
    }

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(verbatim: progress.asset.friendlyName)
                    Text(verbatim: line)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(progress.error != nil ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            } icon: {
                Image(systemName: progress.asset.symbol)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if progress.done {
                Image(systemName: Symbols.active)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Done")
            } else if progress.error != nil {
                Image(systemName: Symbols.error)
                    .font(.title2)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Failed")
            } else if progress.moving {
                DownloadRing(fraction: progress.fraction)
                    .accessibilityLabel("Downloading")
                    .accessibilityValue(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
