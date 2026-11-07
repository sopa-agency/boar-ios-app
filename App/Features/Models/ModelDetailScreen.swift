import BoarModels
import SwiftUI

/// One model's facts behind the list row (progressive disclosure): what it is for, the fit on this iPhone, size and
/// license, the model's name (plus its catalog label, speed and description with technical details on), its page, and delete.
struct ModelDetailScreen: View {
    let asset: CatalogAsset
    let controller: ModelsController
    /// Shown beside the list (Mac): a header instead of the navigation title, and the download button here too.
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    private var present: Bool { controller.isPresent(asset) }
    private var active: Bool { asset.id == controller.activeLlm }
    /// Settings > Advanced > Show Technical Details: the catalog name, the speed and the engine's description.
    private var technicalDetails: Bool { controller.services.settings.showLiveStats }
    private var fit: Compatibility { Compatibility.compute(sizeBytes: asset.sizeBytes, deviceRamBytes: controller.totalRamBytes) }

    /// The Hugging Face repo page ("https://huggingface.co/owner/repo"), not the file itself.
    private var modelPage: URL? {
        guard let url = URL(string: asset.sourceUrl), url.host() == "huggingface.co" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return URL(string: "https://huggingface.co/\(parts[0])/\(parts[1])")
    }

    var body: some View {
        BoarForm {
            if embedded {
                header
            }
            Section {
                Label {
                    Text(verbatim: asset.plainPurpose)
                } icon: {
                    Image(systemName: asset.symbol)
                        .foregroundStyle(.boar(.success))
                }
            } footer: {
                if technicalDetails {
                    BoarFooter { Text(verbatim: asset.description) }
                }
            }

            Section {
                if let label = fit.plainLabel, let symbol = fit.symbol {
                    // Inline symbol: a Label as LabeledContent's value lays the row out several hundred points tall.
                    LabeledContent("Memory") {
                        Text("\(Image(systemName: symbol)) \(Text(label))")
                            .foregroundStyle(fit.style)
                    }
                }
                LabeledContent("Model", value: asset.modelName ?? asset.label)
                LabeledContent("Size", value: asset.sizeBytes.formatted(.byteCount(style: .file)))
                if technicalDetails {
                    LabeledContent("File", value: asset.label)
                    if let speed = asset.capabilities?.estimatedTokensPerSecond, speed > 0 {
                        LabeledContent("Speed on Phones", value: String(localized: "About \(Int(speed.rounded())) tokens per second"))
                    }
                }
                LabeledContent("License", value: asset.license)
            }

            Section {
                if embedded && !present {
                    downloadRow
                }
                if present && !active && asset.kind == .llm {
                    Button("Use This Model", systemImage: Symbols.active, action: use)
                        .disabled(controller.activating != nil)
                }
                if let modelPage {
                    Link(destination: modelPage) {
                        Label("Model Page", systemImage: "safari")
                    }
                    .tint(BoarStyle(role: .link))
                }
            }

            if present && !asset.required {
                Section {
                    Button(role: .destructive, action: askRemove) {
                        Label("Delete Model", systemImage: Symbols.delete)
                            .foregroundStyle(.boar(.danger))
                    }
                    .disabled(controller.activating != nil)
                }
            }
        }
        .navigationTitle(embedded ? AppScreen.models.title : asset.friendlyName)
        .inlineNavigationTitle()
        .confirmationDialog("Delete \(asset.friendlyName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: remove)
        } message: {
            Text("This frees \(FeatureFormat.megabytes(asset.sizeBytes)) on your \(Platform.deviceNoun). You can download it again later.")
        }
    }

    /// The model's name above its facts, when the details sit beside the list.
    private var header: some View {
        Section {
            HStack(spacing: 14) {
                ModelIconTile(symbol: asset.symbol, dimmed: fit == .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: asset.friendlyName)
                        .font(.boar("ui.titleLg"))
                        .foregroundStyle(.boar(.heading))
                    Text(active ? "In use" : present ? "On this \(Platform.deviceNoun)" : "Not downloaded")
                        .foregroundStyle(.boar(active ? .success : .secondary))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var row: ModelsController.Row { controller.rows[asset.id] ?? .init() }

    @ViewBuilder private var downloadRow: some View {
        if row.downloading {
            HStack {
                CatalogDownloadProgress(asset: asset, row: row, showSpeed: technicalDetails)
                Spacer()
                Button("Cancel", role: .cancel) { controller.cancelDownload(asset) }
            }
        } else {
            Button("Download (\(FeatureFormat.megabytes(asset.sizeBytes)))", systemImage: Symbols.download) {
                controller.download(asset)
            }
            .disabled(fit == .red)
        }
    }

    private func use() { controller.use(asset) }
    private func askRemove() { confirmRemove = true }

    private func remove() {
        controller.remove(asset)
        if !embedded { dismiss() }
    }
}
