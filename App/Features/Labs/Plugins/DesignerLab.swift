import BoarCore
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
}

/// The pictures Designer made, newest first, as files in `designer/` under BOAR's files (Erase All Data removes it).
@MainActor
enum DesignerGallery {
    static var dir: URL { AppPaths.filesDir.appending(path: "designer", directoryHint: .isDirectory) }

    static func pictures() -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast }
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { date($0) > date($1) }
    }

    /// Copies the sheet's result (a temporary file) in; nil if it couldn't.
    @discardableResult
    static func keep(_ url: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let target = dir.appending(path: "designer-\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
        do {
            try fm.copyItem(at: url, to: target)
            return target
        } catch {
            BoarLog.logger("labs").error("designer keep: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

/// The page: what to draw (or why it can't here), then the gallery.
private struct DesignerSections: View {
    @State private var pictures: [URL] = DesignerGallery.pictures()
    @State private var shown: URL?

    var body: some View {
        // iOS 18.4 brings the sheet's style choice, which is how the cloud provider stays out.
        if #available(iOS 18.4, macOS 15.4, *) {
            DesignerComposer(pictures: $pictures)
        } else {
            DesignerUnavailable()
        }
        if !pictures.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(pictures, id: \.self) { url in
                        Button {
                            shown = url
                        } label: {
                            DesignerThumbnail(url: url)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Picture"))
                        .contextMenu {
                            ShareLink(item: url)
                            Button("Delete", role: .destructive) { delete(url) }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("On this \(Platform.deviceNoun)")
            }
            .sheet(item: Binding(get: { shown.map(ShownPicture.init) }, set: { shown = $0?.url })) { picture in
                DesignerPictureView(url: picture.url) {
                    delete(picture.url)
                    shown = nil
                }
            }
        }
    }

    private func delete(_ url: URL) {
        DesignerGallery.delete(url)
        pictures = DesignerGallery.pictures()
    }
}

/// What to draw, and Apple's sheet; the reason instead where Image Playground isn't on.
@available(iOS 18.4, macOS 15.4, *)
private struct DesignerComposer: View {
    @Binding var pictures: [URL]
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
                if DesignerGallery.keep(url) != nil { pictures = DesignerGallery.pictures() }
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

/// A gallery cell: the picture, square.
private struct DesignerThumbnail: View {
    let url: URL

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
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
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
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
