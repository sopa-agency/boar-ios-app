import BoarModels
import SwiftUI

/// One answer model: the shared model row (name with the fit badge, what it's for or the download progress, the real
/// model and its size) and one trailing accessory. Tapping a downloaded model switches to
/// it; tapping any other opens its details. Delete lives in the swipe actions and the context menu.
struct CatalogRow: View {
    let asset: CatalogAsset
    let controller: ModelsController
    let onDetails: () -> Void
    @State private var confirmRemove = false
    @State private var confirmUnlist = false

    private var row: ModelsController.Row { controller.rows[asset.id] ?? .init() }
    private var present: Bool { controller.isPresent(asset) }
    private var active: Bool { asset.id == controller.activeLlm }
    private var loading: Bool { controller.activating == asset.id }
    private var fit: Compatibility { Compatibility.compute(sizeBytes: asset.sizeBytes, deviceRamBytes: controller.totalRamBytes) }
    private var tooBig: Bool { !present && fit == .red }
    /// Switching is the row's own action for a model already on the iPhone.
    private var switches: Bool { present && !active }

    var body: some View {
        HStack {
            #if os(macOS)
            // A click selects the row (its details open beside the list); Use This Model is there and in the menu.
            ModelRowContent(asset: asset, fit: fit) {
                status
            }
            #else
            Button(action: primary) {
                ModelRowContent(asset: asset, fit: fit) {
                    status
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(switches && controller.activating != nil)
            .accessibilityHint(switches ? "Answers with this model from now on" : "Shows the model's details")
            #endif

            accessory
        }
        .swipeActions(edge: .trailing) {
            if present && !asset.required {
                Button("Delete", systemImage: Symbols.delete, role: .destructive, action: askRemove)
            } else if !present && controller.isDiscovered(asset) {
                Button("Remove from List", systemImage: Symbols.delete, role: .destructive, action: askUnlist)
            }
        }
        .contextMenu {
            #if !os(macOS)
            Button("Details", systemImage: "info.circle", action: onDetails)
            #endif
            if switches {
                Button("Use This Model", systemImage: Symbols.active, action: use)
            }
            if present && !asset.required {
                Button("Delete", systemImage: Symbols.delete, role: .destructive, action: askRemove)
            } else if !present && controller.isDiscovered(asset) {
                Button("Remove from List", systemImage: Symbols.delete, role: .destructive, action: askUnlist)
            }
        }
        .confirmationDialog("Delete \(asset.friendlyName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: remove)
        } message: {
            Text("This frees \(FeatureFormat.megabytes(asset.sizeBytes)) on your \(Platform.deviceNoun). You can download it again later.")
        }
        .confirmationDialog("Remove from the list?", isPresented: $confirmUnlist, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: unlist)
        } message: {
            Text("This model isn't downloaded. You can add it again with Find More Models.")
        }
    }

    /// The purpose line, or what is happening to the model right now.
    @ViewBuilder private var status: some View {
        if row.downloading {
            CatalogDownloadProgress(asset: asset, row: row, showSpeed: controller.services.settings.showLiveStats)
        } else if row.error != nil {
            Text("Download failed")
                .foregroundStyle(.red)
        } else if loading {
            Text("Loading…")
                .foregroundStyle(.secondary)
        } else {
            Text(verbatim: asset.plainPurpose)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var accessory: some View {
        if row.downloading {
            DownloadProgressButton(fraction: row.progress, onCancel: cancel)
        } else if loading {
            ProgressView()
        } else if active {
            Image(systemName: Symbols.active)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityLabel("In use")
        } else if present || tooBig {
            EmptyView()
        } else if row.error != nil {
            Button("Retry Download", systemImage: Symbols.retry, action: download)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
        } else {
            Button("Download \(asset.friendlyName)", systemImage: Symbols.download, action: download)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
        }
    }

    private func primary() {
        if switches { use() } else { onDetails() }
    }

    private func use() { controller.use(asset) }
    private func download() { controller.download(asset) }
    private func cancel() { controller.cancelDownload(asset) }
    private func askRemove() { confirmRemove = true }
    private func remove() { controller.remove(asset) }
    private func askUnlist() { confirmUnlist = true }
    private func unlist() { controller.removeFromList(asset) }
}
