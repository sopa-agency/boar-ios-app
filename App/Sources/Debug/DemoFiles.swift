#if DEBUG
import BoarModels
import Foundation

/// Demo state on disk: BOAR's files are wiped, then the models the demo calls "installed" are created as sparse files of
/// the catalog's exact size (so `AssetStore.status` says present, the disk gauge has a plausible number, and no GGUF is
/// needed). Nothing here is ever loaded as a model.
enum DemoFiles {
    /// Models and packs the demo has on the phone.
    static let installedIds = ["bge-small-en-v1.5-q8", "qwen2.5-1.5b-instruct-q4km", "corpus-standard"]

    static func reset() {
        guard DebugLaunch.demo else { return }
        let fm = FileManager.default
        // The demo's own settings suite (AppPaths.defaults), never the app's real preferences.
        UserDefaults.standard.removePersistentDomain(forName: "team.sopa.boar.native.demo")
        try? fm.removeItem(at: AppPaths.filesDir)
        try? fm.createDirectory(at: AppPaths.filesDir, withIntermediateDirectories: true)
        AppPaths.markFilesDir(AppPaths.filesDir)
        if UserDefaults.standard.bool(forKey: "uiBasket") { DemoContent.writeBasket() }
        // The setup screens need an empty phone; every other screen needs a ready one.
        if DebugLaunch.screen?.hasPrefix("setup") == true { return }
        guard let catalog = try? Catalog.bundled() else { return }
        for id in installedIds {
            guard let asset = catalog.byId(id) else { continue }
            makeSparse(AppPaths.filesDir.appending(path: asset.filename), size: asset.sizeBytes)
        }
    }

    private static func makeSparse(_ url: URL, size: Int64) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: url.path(percentEncoded: false), contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        try? handle.truncate(atOffset: UInt64(size))
        try? handle.close()
    }
}
#endif
