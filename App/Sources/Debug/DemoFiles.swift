#if DEBUG
import BoarModels
import CoreGraphics
import Foundation
import ImageIO

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
        if UserDefaults.standard.bool(forKey: "uiDesigner") { writeDesignerPictures() }
        // The setup screens need an empty phone; every other screen needs a ready one.
        if DebugLaunch.screen?.hasPrefix("setup") == true { return }
        guard let catalog = try? Catalog.bundled() else { return }
        for id in installedIds {
            guard let asset = catalog.byId(id) else { continue }
            makeSparse(AppPaths.filesDir.appending(path: asset.filename), size: asset.sizeBytes)
        }
    }

    /// `-uiDesigner YES`: three pictures in Boar Designer's gallery (gradients drawn here, no Image Playground needed).
    private static func writeDesignerPictures() {
        let dir = AppPaths.filesDir.appending(path: "designer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.95, 0.45, 0.2), (0.2, 0.6, 0.9), (0.4, 0.8, 0.45)]
        for (i, c) in colors.enumerated() {
            let side = 512
            guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                           colorComponents: [c.0, c.1, c.2, 1, c.0 * 0.3, c.1 * 0.3, c.2 * 0.3, 1],
                                           locations: [0, 1], count: 2) else { continue }
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            let url = dir.appending(path: "designer-demo-\(i).png")
            guard let image = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
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
