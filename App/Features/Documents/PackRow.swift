import BoarModels
import SwiftUI

/// One part of the library: name, what it adds and its size (or the download progress), and one trailing accessory
/// (download, progress with cancel, preparing, or the installed checkmark). Delete is a swipe.
struct PackRow: View {
    let pack: CatalogAsset
    let controller: ModelsController
    @State private var confirmRemove = false

    private var row: ModelsController.Row { controller.rows[pack.id] ?? .init() }
    private var present: Bool { controller.isPresent(pack) }

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(verbatim: pack.friendlyName)
                    subtitle
                        .font(.subheadline)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: Symbols.pack)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .swipeActions(edge: .trailing) {
            if present && !pack.required && !row.indexing {
                Button("Delete", systemImage: Symbols.delete, role: .destructive, action: askRemove)
            }
        }
        .contextMenu {
            if present && !pack.required && !row.indexing {
                Button("Delete", systemImage: Symbols.delete, role: .destructive, action: askRemove)
            }
        }
        .confirmationDialog("Delete \(pack.friendlyName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: remove)
        } message: {
            Text("This frees \(FeatureFormat.megabytes(pack.sizeBytes)) on your \(Platform.deviceNoun). Its topics can't be searched until you download it again.")
        }
    }

    @ViewBuilder private var subtitle: some View {
        if row.downloading {
            CatalogDownloadProgress(asset: pack, row: row, showSpeed: controller.services.settings.showLiveStats)
        } else if row.indexing {
            Text("Preparing for search…")
                .foregroundStyle(.secondary)
        } else if row.error != nil {
            Text("Download failed")
                .foregroundStyle(.red)
        } else {
            Text(verbatim: "\(pack.plainPurpose) · \(FeatureFormat.megabytes(pack.sizeBytes))")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var accessory: some View {
        if row.downloading {
            DownloadProgressButton(fraction: row.progress, onCancel: cancel)
        } else if row.indexing {
            ProgressView()
        } else if present {
            Image(systemName: Symbols.active)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityLabel("Installed")
        } else if row.error != nil {
            Button("Retry Download", systemImage: Symbols.retry, action: download)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
        } else {
            Button("Download \(pack.friendlyName)", systemImage: Symbols.download, action: download)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
        }
    }

    private func download() { controller.download(pack) }
    private func cancel() { controller.cancelDownload(pack) }
    private func askRemove() { confirmRemove = true }
    private func remove() { controller.remove(pack) }
}
