import BoarAppleAI
import BoarCore
import BoarRAG
import CoreGraphics
import Foundation
import ImageIO
import Observation
import PDFKit

/// My Documents (port of android `DocumentsViewModel`, itself PersonalDocumentsManager.tsx): import files or photos of
/// pages into a named collection, switch it on or off, export or remove it. Everything is read and indexed on the phone.
@MainActor
@Observable
final class DocumentsController {
    enum Stage: Equatable {
        case reading
        case recognizing(done: Int, total: Int)
        case chunking
        case embedding(done: Int, total: Int)
    }

    private(set) var collections: [KnowledgeBase.Collection] = []
    private(set) var stage: Stage?
    var error: String?
    /// The collection just imported (VoiceOver announcement, toast).
    var imported: String?

    @ObservationIgnored let services: BoarServices
    @ObservationIgnored private let stop = StopFlag()

    init(services: BoarServices) {
        self.services = services
    }

    var busy: Bool { stage != nil }

    func refresh() async {
        collections = (try? await services.background { try $0.knowledgeBase.collections() }) ?? []
    }

    /// Files picked with the document picker: text, Markdown, CSV, JSON and PDF. A PDF without selectable text is read
    /// with on-device OCR (Vision), which the Android app doesn't do.
    func importFiles(_ urls: [URL], name: String) {
        guard !urls.isEmpty, !busy else { return }
        run(name: name) { controller in
            var files: [DocumentImport.File] = []
            let recognizer = DocumentTextRecognizer()
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let fileName = url.lastPathComponent
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let text: String
                if url.pathExtension.lowercased() == "pdf" {
                    text = try await Self.pdfText(url, fileName: fileName, recognizer: recognizer) { done, total in
                        Task { @MainActor in controller.stage = .recognizing(done: done, total: total) }
                    }
                } else {
                    guard let data = try? Data(contentsOf: url) else { throw ImportError(String(localized: "Couldn't read \"\(fileName)\".")) }
                    text = String(decoding: data, as: UTF8.self)
                }
                files.append(DocumentImport.File(name: fileName, sizeBytes: size > 0 ? size : Int64(text.utf8.count), text: text))
            }
            return files
        }
    }

    /// Photos of pages (PhotosPicker): each one's text, recognized on the phone, becomes a document of the collection.
    func importPhotos(_ images: [Data], name: String) {
        guard !images.isEmpty, !busy else { return }
        run(name: name) { controller in
            let recognizer = DocumentTextRecognizer()
            var files: [DocumentImport.File] = []
            for (i, data) in images.enumerated() {
                Task { @MainActor in controller.stage = .recognizing(done: i, total: images.count) }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw ImportError(String(localized: "Photo \(i + 1) couldn't be read."))
                }
                let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32
                let text = try await recognizer.recognize(image, orientation: orientation.flatMap(CGImagePropertyOrientation.init(rawValue:)))
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let title = String(localized: "\(name) page \(i + 1)")
                files.append(DocumentImport.File(name: "\(title).txt", sizeBytes: Int64(text.utf8.count), text: text))
            }
            if files.isEmpty { throw ImportError(String(localized: "No text was found in the photos.")) }
            return files
        }
    }

    /// Stops an import between chunks; the half-made collection is removed.
    func cancelImport() { stop.set(true) }

    private func run(name: String, read: @escaping @Sendable (DocumentsController) async throws -> [DocumentImport.File]) {
        stage = .reading
        error = nil
        imported = nil
        stop.set(false)
        let services = services
        let stop = stop
        let throttle = Throttle(interval: 0.2)
        Task {
            do {
                let files = try await Task.detached(priority: .userInitiated) { try await read(self) }.value
                stage = .chunking
                try await Task.detached(priority: .userInitiated) {
                    _ = try await DocumentImport.importDocuments(
                        kb: services.knowledgeBase,
                        embed: { text in try await services.embedder.embed(text, catalog: services.catalog) },
                        files: files, collectionName: name,
                        onProgress: { done, total in
                            guard throttle.ready(force: done >= total) else { return }
                            Task { @MainActor in self.stage = .embedding(done: done, total: total) }
                        },
                        shouldStop: { stop.value }
                    )
                }.value
                imported = name
            } catch is SeedCorpus.Stopped {
            } catch {
                self.error = error.localizedDescription
            }
            stage = nil
            await refresh()
        }
    }

    /// A collection's on/off switch as a bindable value; writes go through `setActive`.
    subscript(activeFor id: String) -> Bool {
        get { collections.first { $0.id == id }?.active ?? false }
        set { setActive(id, newValue) }
    }

    func setActive(_ id: String, _ on: Bool) {
        if let i = collections.firstIndex(where: { $0.id == id }) { collections[i].active = on }
        Task {
            _ = try? await services.background { try $0.knowledgeBase.setCollectionActive(id, on) }
            await refresh()
        }
    }

    func remove(_ id: String) {
        Task {
            _ = try? await services.background { try $0.knowledgeBase.deleteCollection(id) }
            await refresh()
        }
    }

    /// exportCollection: the collection's passages as JSON (importable again here or in the other apps).
    func exportFile(_ c: KnowledgeBase.Collection) -> ExportedFile {
        let services = services
        let id = c.id
        let slug = DocumentImport.slug(c.name)
        return ExportedFile(filename: (slug.isEmpty ? "collection" : slug) + ".json") {
            let json = try await services.background { DocumentImport.exportJson(try $0.knowledgeBase.collectionDocs(id)) }
            return Data(json.utf8)
        }
    }

    // MARK: reading

    struct ImportError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// The PDF's selectable text (PDFKit); a scanned PDF, with none, goes through OCR page by page.
    nonisolated private static func pdfText(_ url: URL, fileName: String, recognizer: DocumentTextRecognizer,
                                            progress: @escaping @Sendable (Int, Int) -> Void) async throws -> String {
        guard let doc = PDFDocument(url: url) else { throw ImportError(String(localized: "Couldn't read \"\(fileName)\".")) }
        if doc.isLocked { throw ImportError(String(localized: "\"\(fileName)\" is password-protected. Password-protected PDFs aren't supported.")) }
        let text = doc.string ?? ""
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        progress(0, doc.pageCount)
        let recognized = try await recognizer.recognize(fileURL: url)
        progress(doc.pageCount, doc.pageCount)
        guard !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError(String(localized: "\"\(fileName)\" has no text BOAR could read."))
        }
        return recognized
    }
}
