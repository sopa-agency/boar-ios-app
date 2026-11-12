import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Each Boar Avatar's picture (Android's `TruffleArt`): `truffle_<id>.heic` in the app bundle, 512 px, written by
/// `scripts/import-truffles.py` from Android's hi-res art. Loose files instead of the asset catalog, which would keep a
/// decoded copy of each one (12 MB instead of 2.2 MB).
@MainActor
enum TruffleArt {
    #if canImport(UIKit)
    private typealias Picture = UIImage
    #else
    private typealias Picture = NSImage
    #endif

    /// Decoded pictures, given back to the system under memory pressure (the models need it more than the grid).
    private static let cache = NSCache<NSString, Picture>()

    /// The avatar's picture, or nil for an id with no art in this build.
    static func image(_ id: String) -> Image? {
        guard let picture = picture(id) else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: picture)
        #else
        return Image(nsImage: picture)
        #endif
    }

    private static func picture(_ id: String) -> Picture? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        guard let url = Bundle.main.url(forResource: "truffle_\(id)", withExtension: "heic") else { return nil }
        #if canImport(UIKit)
        let picture = UIImage(contentsOfFile: url.path)
        #else
        let picture = NSImage(contentsOf: url)
        #endif
        if let picture { cache.setObject(picture, forKey: id as NSString) }
        return picture
    }
}
