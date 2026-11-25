import Foundation

/// Boar Designer's picture sizes (android engine `labs/DesignerCanvas.kt`, the size half): a drawing's shape and quality
/// instead of its pixel size. iOS has no Designer yet; Press's receipt names a drawing's shape and quality with it, as
/// Android's does (a basket migrated from a drawing, or a project shared from Android).
public enum DesignerCanvas {
    /// `key`: the shape's word key; "banner" is the old key of Wide, kept.
    public enum Shape: String, Sendable, CaseIterable {
        case square, portrait, wide = "banner"
    }

    /// The three sizes of a shape, smallest to largest.
    public enum Quality: String, Sendable, CaseIterable { case low, medium, high }

    /// A drawing's size in pixels.
    public struct Size: Sendable, Equatable, Hashable {
        public var w: Int
        public var h: Int
        public init(_ w: Int, _ h: Int) { self.w = w; self.h = h }

        /// "512" for a square (the key older saves and times used), "384x512" otherwise.
        public var key: String { w == h ? "\(w)" : "\(w)x\(h)" }
        public var shape: Shape { w == h ? .square : h > w ? .portrait : .wide }
        /// Its own level among its shape's three sizes; a size that is none of them reads as Medium.
        public var quality: Quality { Quality.allCases.first { DesignerCanvas.size(shape, $0) == self } ?? .medium }
    }

    /// The size `shape` draws at in `quality`.
    public static func size(_ shape: Shape, _ quality: Quality) -> Size {
        switch (shape, quality) {
        case (.square, .low): Size(384, 384)
        case (.square, .medium): Size(512, 512)
        case (.square, .high): Size(640, 640)
        case (.portrait, .low): Size(320, 448)
        case (.portrait, .medium): Size(384, 512)
        case (.portrait, .high): Size(448, 640)
        case (.wide, .low): Size(576, 256)
        case (.wide, .medium): Size(640, 320)
        case (.wide, .high): Size(768, 320)
        }
    }
}
