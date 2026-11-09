import BoarModels
import SwiftUI

/// A download's one secondary line in Android's mono.xs progress line (ModelsScreen.kt): the bytes in textDim, the
/// speed in bold cyan (only with technical details on), the time left in amber: "1.0 GB of 2.3 GB · about 3 min left".
struct CatalogDownloadProgress: View {
    let asset: CatalogAsset
    let row: ModelsController.Row
    let showSpeed: Bool

    private var line: Text {
        if row.verifying {
            return Text("Checking…").foregroundStyle(.boar(.link))
        }
        let separator = Text(verbatim: " · ").foregroundStyle(.boar(.dim))
        var line = Text("\(FeatureFormat.megabytes(row.bytesWritten)) of \(FeatureFormat.megabytes(asset.sizeBytes))")
            .foregroundStyle(.boar(.dim))
        if showSpeed, let speed = FeatureFormat.speed(row.speedBytesPerSec) {
            line = line + separator + Text(verbatim: speed).bold().foregroundStyle(.boar(.link))
        }
        if let eta = FeatureFormat.eta(row.etaSeconds) {
            line = line + separator + Text("about \(eta) left").fontWeight(.semibold).foregroundStyle(.boar(.amber))
        }
        return line
    }

    var body: some View {
        line
            .boarText("mono.xs")
    }
}
