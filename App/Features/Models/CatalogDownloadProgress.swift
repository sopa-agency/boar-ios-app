import BoarModels
import SwiftUI

/// A download's one secondary line: "1.0 GB of 2.3 GB · about 3 min left" (speed only with technical details on).
struct CatalogDownloadProgress: View {
    let asset: CatalogAsset
    let row: ModelsController.Row
    let showSpeed: Bool

    private var line: String {
        if row.verifying { return String(localized: "Checking…") }
        var parts = [String(localized: "\(FeatureFormat.megabytes(row.bytesWritten)) of \(FeatureFormat.megabytes(asset.sizeBytes))")]
        if let eta = FeatureFormat.eta(row.etaSeconds) { parts.append(String(localized: "about \(eta) left")) }
        if showSpeed, let speed = FeatureFormat.speed(row.speedBytesPerSec) { parts.append(speed) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Text(verbatim: line)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}
