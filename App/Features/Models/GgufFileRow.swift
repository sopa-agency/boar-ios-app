import BoarModels
import SwiftUI

/// An open repo's GGUF files: the recommended one first, the other versions behind one tap. A file that is downloading
/// or already on this device stays in view.
struct GgufFileList: View {
    let repo: String
    let controller: ModelsController
    @State private var showAll = false

    private var recommended: String? { HfQuery.recommended(controller.hfFiles.map(\.filename)) }

    private func shown(_ file: HfBrowser.GgufFile) -> Bool {
        if showAll || recommended == nil || file.filename == recommended { return true }
        guard let asset = controller.hfAsset(repo, file) else { return false }
        return controller.isPresent(asset) || controller.rows[asset.id]?.downloading == true
    }

    var body: some View {
        let files = controller.hfFiles.sorted { a, b in (a.filename == recommended ? 0 : 1) < (b.filename == recommended ? 0 : 1) }
        let hidden = files.filter { !shown($0) }.count
        ForEach(files.filter(shown)) { file in
            GgufFileRow(repo: repo, file: file, recommended: file.filename == recommended, controller: controller)
        }
        if hidden > 0 {
            Button("Other Versions (\(hidden))", systemImage: "chevron.down") { showAll = true }
                .font(.boar("ui.subtext"))
                .tint(BoarStyle(role: .link))
        }
    }
}

/// One GGUF file in an open repo: what kind of version it is in plain words, its size and fit on this device, and a
/// Download button that downloads it right here (it also lands in Models), then Use once it's on the device.
struct GgufFileRow: View {
    let repo: String
    let file: HfBrowser.GgufFile
    let recommended: Bool
    let controller: ModelsController

    private var asset: CatalogAsset? { controller.hfAsset(repo, file) }
    private var row: ModelsController.Row { asset.flatMap { controller.rows[$0.id] } ?? .init() }
    private var present: Bool { asset.map(controller.isPresent) ?? false }
    private var active: Bool { asset?.id == controller.activeLlm }
    private var fit: Compatibility { Compatibility.compute(sizeBytes: file.sizeBytes, deviceRamBytes: controller.totalRamBytes) }

    private var quant: String? { HfQuery.quant(file.filename) }
    private var title: String {
        quant ?? file.filename.replacing(/\.gguf$/.ignoresCase(), with: "")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                // Android's file row (BrowseScreen.kt): the name in subtext textPrimary, the facts under it in micro.
                Text(verbatim: title)
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(.boar(.primary))
                status
                CompatibilityLabel(fit: fit)
            }
            Spacer()
            accessory
        }
    }

    /// What the version is ("Balanced size and quality · 1.1 GB"), or the download's progress.
    @ViewBuilder private var status: some View {
        if row.downloading, let asset {
            CatalogDownloadProgress(asset: asset, row: row, showSpeed: controller.services.settings.showLiveStats)
        } else if let error = row.error {
            Text(verbatim: error)
                .font(.boar("ui.caption"))
                .foregroundStyle(.boar(.danger))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 4) {
                if let level = quant.flatMap(HfQuery.quantLevel) {
                    Text(Self.describe(level))
                    Text(verbatim: "·")
                }
                Text(file.sizeBytes, format: .byteCount(style: .file))
                    .monospacedDigit()
                if recommended {
                    Text(verbatim: "·")
                    Text("Recommended")
                }
            }
            .font(.boar("ui.micro"))
            .foregroundStyle(.boar(recommended ? .success : .dim))
        }
    }

    @ViewBuilder private var accessory: some View {
        if row.downloading, let asset {
            DownloadProgressButton(fraction: row.progress) { controller.hfCancel(asset) }
        } else if active {
            Image(icon: Symbols.active)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityLabel("In use")
        } else if present, let asset {
            Button("Use") { controller.use(asset) }
                .buttonStyle(.bordered)
                .disabled(controller.activating != nil)
        } else {
            Button(row.error != nil ? "Retry Download" : "Download \(title)",
                   icon: row.error != nil ? Symbols.retry : Symbols.download) {
                controller.hfDownload(repo, file)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.title2)
            .disabled(fit == .red)
        }
    }

    private static func describe(_ level: HfQuery.QuantLevel) -> LocalizedStringKey {
        switch level {
        case .smallest: "Smallest, answers noticeably worse"
        case .small: "Small, some loss in quality"
        case .balanced: "Balanced size and quality"
        case .better: "Better quality, bigger"
        case .high: "Near full quality, large"
        case .full: "Full quality, largest"
        }
    }
}
