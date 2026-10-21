import SwiftUI

/// The library index that runs once every file is on the iPhone, in the same row shape as the downloads.
struct IndexRow: View {
    let flow: SetupFlow

    private var line: String {
        switch flow.indexPhase {
        case .waiting: String(localized: "Starts after the downloads")
        case .building:
            flow.indexTotal > 0 ? String(localized: "\(flow.indexDone) of \(flow.indexTotal) articles") : String(localized: "Preparing for search…")
        case .ready: String(localized: "Ready to search")
        case .error: String(localized: "Couldn't prepare the library")
        }
    }

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text("Library")
                    Text(verbatim: line)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(flow.indexPhase == .error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            } icon: {
                Image(systemName: Symbols.library)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch flow.indexPhase {
            case .waiting: EmptyView()
            case .building:
                if flow.indexTotal > 0 {
                    DownloadRing(fraction: Double(flow.indexDone) / Double(max(flow.indexTotal, 1)))
                } else {
                    ProgressView()
                }
            case .ready:
                Image(systemName: Symbols.active).font(.title2).foregroundStyle(.tint).accessibilityLabel("Done")
            case .error:
                Image(systemName: Symbols.error).font(.title2).foregroundStyle(.red).accessibilityLabel("Failed")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
