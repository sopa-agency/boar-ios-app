#if DEBUG
import BoarAnswer
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
        if UserDefaults.standard.bool(forKey: "uiPressPage") { writePressPage() }
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

    /// `-uiPressPage YES`: Boar Press's open project as a written page: a heading, paragraphs, a photo on the left with
    /// a caption and text beside it, a list and one of the demo chats' answers.
    private static func writePressPage() {
        let now: Int64 = 1_793_000_000_000
        let dir = PressStore.dir(AppPaths.filesDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var blocks: [PressDoc.Block] = [
            .heading(id: "demo-h1", text: "Why the sea is salty"),
            .paragraph(id: "demo-t1", text: "We walked the salt flats at low tide and tasted the water at three places along the shore. It was saltiest where the pools had dried in the sun."),
        ]
        if let data = shorePhoto(),
           var pic = try? PressFiles.copyPhoto(data, pressDir: dir, projectId: "demo-press", blockId: "demo-pic", name: "photo-demo.jpg") {
            pic.caption = "Salt crust on a dried pool"
            pic.place = .left
            blocks.append(.picture(pic))
        }
        blocks.append(.paragraph(id: "demo-t2", text: "The white crust is mostly sodium chloride. Rain wears it off the rocks inland, the rivers bring it down to the sea, and when the water evaporates the salt stays behind."))
        blocks.append(.bullets(id: "demo-l1", text: "Bring a water bottle\nCheck the tide table\nTake a jar for a sample"))
        var lib = PressDoc.Library("demo-press", [PressDoc.Project("demo-press", "Coast walk", now, blocks)])
        if let s = DemoContent.sessions.first(where: { $0.title == "What is plate tectonics?" }), let e = s.exchanges.first {
            lib = lib.addAnswer(PressDoc.Answer("demo-page-answer", s.title, e.question, e.answer,
                                                e.sources.map { PressDoc.Source($0.title, $0.source) }, now + 1,
                                                DemoContent.model, e.receipt.tokPerSec))
        }
        lib = lib.markSeen(now + 2)
        try? Data(PressDoc.toJson(lib).utf8).write(to: PressStore.projectsURL(AppPaths.filesDir), options: .atomic)
    }

    /// A 900 × 600 PNG drawn here: a pale shore, the sea, the sky and the sun.
    private static func shorePhoto() -> Data? {
        let w = 900, h = 600
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // The origin is the bottom left: shore, sea, then sky.
        let bands: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0.42, 0.9, 0.86, 0.78), (0.42, 0.62, 0.2, 0.46, 0.64), (0.62, 1, 0.62, 0.8, 0.95),
        ]
        for (from, to, r, g, b) in bands {
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            ctx.fill(CGRect(x: 0, y: CGFloat(h) * from, width: CGFloat(w), height: CGFloat(h) * (to - from)))
        }
        ctx.setFillColor(red: 1, green: 0.88, blue: 0.55, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: 640, y: 440, width: 90, height: 90))
        ctx.setFillColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: 120, y: 60, width: 420, height: 110))
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
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
