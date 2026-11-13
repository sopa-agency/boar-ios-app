import BoarCore
import ImageIO
import ImagePlayground
import SwiftUI

/// Boar Designer (android labs/plugins/image) through Apple's Image Playground, decided 2026-11-12 (docs/labs-ios.md):
/// no 683 MB model, only where Apple Intelligence is on (iPhone 15 Pro and later, Apple silicon Macs). The words go to
/// Apple's sheet, the user picks the style there (animation, illustration, sketch; never the cloud provider), and the
/// picture is kept in BOAR's files. Not ported: Designer's own styles, sizes, seeds and Regenerate, and Illustrate under
/// answers (Apple's sheet would ask for every one).
struct DesignerLab: LabPlugin {
    let id = "image"
    let order = 20
    let emoji = "🎨"
    let art: String? = "truffle_retrowave"
    /// Android's is BETA; this one hasn't drawn on a phone yet (none of the test phones has Apple Intelligence).
    let status = LabStatus.alpha
    var title: String { String(localized: "Boar Designer") }
    var body: String { String(localized: "Draw an illustration from a few words with Apple's Image Playground, on this \(Platform.deviceNoun).") }

    func content() -> AnyView { AnyView(DesignerSections()) }
    func presenter() -> AnyView? { AnyView(DesignerPresenter()) }
}

/// The pictures Designer made, newest first, as files in `designer/` under BOAR's files, and the one open in the sheet.
/// Erase All Data and the lock's Forgot PIN erase them; Clear Chats keeps them, as Android's CHATS scope does.
@MainActor @Observable
final class DesignerGallery {
    static let shared = DesignerGallery()

    private(set) var pictures: [URL] = []
    /// The picture open in the page's sheet (`DesignerPresenter`).
    var shown: URL?
    /// The last picture from Apple's sheet couldn't be kept.
    var keepFailed = false

    static var dir: URL { AppPaths.filesDir.appending(path: "designer", directoryHint: .isDirectory) }

    func reload() {
        let keys: Set<URLResourceKey> = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: Array(keys))) ?? []
        pictures = files.filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { ($0, (try? $0.resourceValues(forKeys: keys).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Copies the sheet's result (a temporary file) in.
    func keep(_ url: URL) {
        let fm = FileManager.default
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let target = Self.dir.appending(path: "designer-\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
        do {
            try fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: target)
        } catch {
            BoarLog.logger("labs").error("designer keep: \(error.localizedDescription, privacy: .public)")
            keepFailed = true
        }
        reload()
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if shown == url { shown = nil }
        reload()
    }

    /// Every picture, and the sheet closes.
    func erase() {
        try? FileManager.default.removeItem(at: Self.dir)
        shown = nil
        reload()
    }
}

/// The page: what to draw (or why it can't here), then the gallery.
private struct DesignerSections: View {
    let gallery = DesignerGallery.shared

    var body: some View {
        // iOS 18.4 brings the sheet's style choice, which is how the cloud provider stays out.
        if #available(iOS 18.4, macOS 15.4, *) {
            DesignerComposer()
        } else {
            DesignerUnavailable()
        }
        if !gallery.pictures.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(gallery.pictures, id: \.self) { url in
                        Button {
                            gallery.shown = url
                        } label: {
                            DesignerThumbnail(url: url)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Picture"))
                        .accessibilityIdentifier("designer.picture")
                        .contextMenu {
                            ShareLink(item: url)
                            Button("Delete", role: .destructive) { gallery.delete(url) }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("On this \(Platform.deviceNoun)")
            }
        }
    }
}

/// The open picture's sheet, behind the whole lab page (`LabPlugin.presenter`).
private struct DesignerPresenter: View {
    @Bindable private var gallery = DesignerGallery.shared

    var body: some View {
        Color.clear
            .sheet(item: Binding(get: { gallery.shown.map(ShownPicture.init) }, set: { gallery.shown = $0?.url })) { picture in
                DesignerPictureView(url: picture.url) { gallery.delete(picture.url) }
            }
            .alert("Couldn't keep the picture.", isPresented: $gallery.keepFailed) {
                Button("OK", role: .cancel) {}
            }
            .onAppear { gallery.reload() }
    }
}

/// What to draw, and Apple's sheet; the reason instead where Image Playground isn't on.
@available(iOS 18.4, macOS 15.4, *)
private struct DesignerComposer: View {
    @Environment(\.supportsImagePlayground) private var supported
    @State private var subject = ""
    @State private var drawing = false

    private var concept: String { subject.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if supported {
            Section {
                TextField(String(localized: "a wild boar"), text: $subject, axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("designer.subject")
                Button("Draw") { drawing = true }
                    .disabled(concept.isEmpty)
                    .accessibilityIdentifier("designer.draw")
            } header: {
                Text("What to draw")
            } footer: {
                BoarFooter {
                    Text("Apple's Image Playground opens with your words: pick a style there (animation, illustration or sketch) and keep the picture you like. It is drawn on this \(Platform.deviceNoun), and BOAR keeps it here.")
                }
            }
            .imagePlaygroundSheet(isPresented: $drawing, concept: concept) { url in
                DesignerGallery.shared.keep(url)
            }
            // On-device styles only: BOAR is offline, so never the external (cloud) provider.
            .imagePlaygroundGenerationStyle(.illustration, in: [.animation, .illustration, .sketch])
        } else {
            DesignerUnavailable()
        }
    }
}

/// Where Image Playground isn't: why, and that Android draws with its own model.
private struct DesignerUnavailable: View {
    var body: some View {
        Section {
            Text("Boar Designer draws with Apple's Image Playground, which needs Apple Intelligence (an iPhone 15 Pro or later, or a Mac with Apple silicon) on iOS 18.4 or macOS 15.4 or later, turned on in Settings. It isn't available on this \(Platform.deviceNoun).")
        } footer: {
            BoarFooter {
                Text("On Android, Boar Designer draws with its own model. On iPhone and Mac it uses Apple's instead, so there is nothing to download.")
            }
        }
    }
}

private struct ShownPicture: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A gallery cell: the picture, square, decoded at cell size.
private struct DesignerThumbnail: View {
    let url: URL

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                DesignerImage(url: url, maxPixels: 320) { image in
                    image.resizable().scaledToFill()
                } placeholder: { failed in
                    Rectangle().fill(.boar(.border))
                        .overlay { if failed { Image(systemName: "photo").foregroundStyle(.boar(.dim)) } }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
    }
}

/// One picture, whole, with Share and Delete.
private struct DesignerPictureView: View {
    let url: URL
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DesignerImage(url: url, maxPixels: 2048) { image in
                image.resizable().scaledToFit()
            } placeholder: { failed in
                if failed {
                    Text("Couldn't open the picture.").foregroundStyle(.boar(.muted))
                } else {
                    ProgressView()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text("Picture"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
        }
        .macSheetSize(width: 560, height: 600)
    }
}

/// A picture file decoded off the main thread, no larger than `maxPixels` on its long side (ImageIO's thumbnail, so a
/// gallery cell doesn't hold the whole PNG); `placeholder(true)` when the file can't be read.
private struct DesignerImage<Content: View, Placeholder: View>: View {
    let url: URL
    let maxPixels: Int
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: (_ failed: Bool) -> Placeholder
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                content(Image(decorative: image, scale: 1))
            } else {
                placeholder(failed)
            }
        }
        .task(id: url) {
            let url = url, maxPixels = maxPixels
            let decoded = await Task.detached(priority: .userInitiated) { decodePicture(url, maxPixels: maxPixels) }.value
            image = decoded
            failed = decoded == nil
        }
    }
}

/// `DesignerImage`'s decode, outside the generic view so the detached task captures none of its types.
nonisolated private func decodePicture(_ url: URL, maxPixels: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}
