import SwiftUI

/// The install step's title and overall progress: the download, then the library index.
struct InstallProgressSection: View {
    let flow: SetupFlow
    let title: LocalizedStringKey

    private var fraction: Double { flow.totalBytes > 0 ? Double(flow.doneBytes) / Double(flow.totalBytes) : 0 }

    var body: some View {
        SetupHeader(title: title,
                    message: flow.allPresent
                        ? "BOAR is indexing your library so it can search it. No internet needed for this part."
                        : "This is the only time BOAR uses the internet. Downloads continue in the background.")
        Section {
            if !flow.allPresent {
                ProgressView(value: fraction) {
                    Text("\(FeatureFormat.megabytes(flow.doneBytes)) of \(FeatureFormat.megabytes(flow.totalBytes))")
                        .monospacedDigit()
                } currentValueLabel: {
                    if let eta = FeatureFormat.eta(flow.etaSeconds.map(Double.init)) { Text("About \(eta) left") }
                }
            } else if flow.indexTotal > 0 {
                ProgressView(value: Double(flow.indexDone), total: Double(flow.indexTotal)) {
                    Text("\(flow.indexDone.formatted()) of \(flow.indexTotal.formatted()) articles")
                        .monospacedDigit()
                } currentValueLabel: {
                    if let eta = FeatureFormat.eta(flow.indexEtaSeconds.map(Double.init)) { Text("About \(eta) left") }
                }
            } else {
                ProgressView {
                    Text("Preparing the library for search…")
                }
            }
        }
    }
}
