import BoarAppleAI
import BoarCore
import BoarModels
import BoarRAG
import CryptoKit
import Foundation
import Observation

/// The files picked on setup's files page (android SetupViewModel's addFiles / removeFile / importQueued): each one is
/// copied into `setup-imports/` at once (the picker's access doesn't last), then imported into one Personal Files
/// collection when it can be (SetupGuide.canImport). `.import.json` records the last import: its collection, replaced
/// by the next import, and the files it took.
@MainActor
@Observable
final class SetupFiles {
    /// The picked files (names in the folder), sorted, and the ones the last finished import took.
    private(set) var files: [String] = []
    private(set) var imported: [String] = []
    private(set) var importing = false
    /// The last pick's or import's files that couldn't go in, and the ones skipped as already picked.
    private(set) var errors: [String] = []
    private(set) var notes: [String] = []

    @ObservationIgnored private let services: BoarServices
    @ObservationIgnored private var job: Task<Void, Never>?
    /// Whether setup's index is building now: no import while it runs (SetupGuide.canImport).
    @ObservationIgnored var indexBuilding: () -> Bool = { false }

    init(services: BoarServices) {
        self.services = services
        reload()
    }

    nonisolated static func folder(_ filesDir: URL) -> URL { filesDir.appending(path: "setup-imports", directoryHint: .isDirectory) }

    /// Erase: the waiting copies too (android PinLock's eraseOwnFiles). Throws when the folder stays.
    nonisolated static func eraseFolder(_ filesDir: URL) throws {
        let dir = folder(filesDir)
        guard FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    private var dir: URL { Self.folder(services.filesDir) }
    private var record: URL { dir.appending(path: ".import.json") }

    var pending: [String] { SetupGuide.pending(onDisk: files, imported: imported) }

    private func reload() {
        files = Self.picked(dir)
        imported = Self.lastImport(record).files
    }

    /// The folder's files, without its own hidden ones (.import.json, copies still being written).
    nonisolated private static func picked(_ dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    nonisolated private static func lastImport(_ record: URL) -> (collectionId: String?, files: [String]) {
        guard let data = try? Data(contentsOf: record), let o = JSONValue(jsonString: String(decoding: data, as: UTF8.self)) else { return (nil, []) }
        let id = o["collectionId"]?.stringValue ?? ""
        return (id.isEmpty ? nil : id, o["files"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }

    nonisolated private static func record(_ url: URL, collectionId: String?, files: [String]) {
        let o: JSONValue = .object(["collectionId": .string(collectionId ?? ""), "files": .array(files.map { .string($0) })])
        try? Data(o.jsonString.utf8).write(to: url, options: .atomic)
    }

    nonisolated private static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: picking

    /// The page's picker: each file copied at once. A kind BOAR can't read, or one too large, is turned away here with the
    /// same line as Knowledge → Personal Files; the same bytes picked twice go in once.
    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let dir = dir
        Task {
            let (errors, notes) = await Task.detached(priority: .userInitiated) { Self.copy(urls, into: dir) }.value
            self.errors = errors
            self.notes = notes
            files = Self.picked(dir)
            importQueued()
        }
    }

    nonisolated private static func copy(_ urls: [URL], into dir: URL) -> (errors: [String], notes: [String]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var errors: [String] = [], notes: [String] = []
        var have: [String: String] = [:]
        for n in picked(dir) { if let h = sha256(dir.appending(path: n)) { have[h] = n } }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Only the last segment, and no leading dot, which would hide it with the folder's own files.
            let name = String(url.lastPathComponent.drop { $0 == "." })
            guard !name.isEmpty, DocumentImport.readable(name) else {
                errors.append(DocumentsController.unsupported(url.lastPathComponent).message)
                continue
            }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if DocumentImport.tooLargeToRead(size) {
                errors.append(DocumentsController.tooLarge(name).message)
                continue
            }
            let target = dir.appending(path: SetupGuide.freeName(name, taken: Set(picked(dir))))
            // Copied under a hidden name, then moved: an import running meanwhile only sees whole files.
            let part = dir.appending(path: ".\(target.lastPathComponent).part")
            try? fm.removeItem(at: part)
            guard (try? fm.copyItem(at: url, to: part)) != nil, let hash = sha256(part) else {
                try? fm.removeItem(at: part)
                errors.append(DocumentsController.unreadable(name).message)
                continue
            }
            if let same = have[hash] {
                try? fm.removeItem(at: part)
                notes.append(String(localized: "Already added: \(same)"))
            } else if (try? fm.moveItem(at: part, to: target)) == nil {
                try? fm.removeItem(at: part)
                errors.append(DocumentsController.unreadable(name).message)
            } else {
                have[hash] = target.lastPathComponent
            }
        }
        return (errors, notes)
    }

    /// The page's ✕: the copy goes. Once an import took it, the collection is made again without it (the next import
    /// replaces the last one's); with no file left, the collection goes too. After a running import.
    func remove(_ name: String) {
        let dir = dir, record = record, services = services
        Task {
            await job?.value
            await Task.detached {
                try? FileManager.default.removeItem(at: dir.appending(path: name))
                let (lastId, done) = Self.lastImport(record)
                guard done.contains(name) else { return }
                if Self.picked(dir).isEmpty {
                    if let lastId { _ = try? await services.background { try $0.knowledgeBase.deleteCollection(lastId) } }
                    try? FileManager.default.removeItem(at: record)
                } else {
                    // All pending again: imported again without it.
                    Self.record(record, collectionId: lastId, files: [])
                }
            }.value
            errors = []
            notes = []
            reload()
            importQueued()
        }
    }

    // MARK: import

    /// Imports every picked file into one collection when it can: on a pick, after each download, when the index is done,
    /// and when setup resumes or ends. Each import replaces the last one's collection, so a second batch, or an import
    /// the process didn't finish, never leaves a duplicate or a half collection.
    func importQueued() {
        reload()
        guard !pending.isEmpty else { return }
        let search = !services.installed(.embedding).isEmpty
        guard SetupGuide.canImport(searchModelPresent: search, indexBuilding: indexBuilding(), importing: job != nil) else { return }
        let dir = dir, record = record, services = services
        let names = files
        let name = String(localized: "Setup files")
        importing = true
        job = Task {
            let newErrors = await Task.detached(priority: .userInitiated) { () -> [String] in
                var errors: [String] = []
                let (lastId, done) = Self.lastImport(record)
                do {
                    if let lastId { _ = try await services.background { try $0.knowledgeBase.deleteCollection(lastId) } }
                    let id = DocumentImport.collectionId(name)
                    // Recorded before the first passage: a process killed mid-import leaves a collection the next one removes.
                    Self.record(record, collectionId: id, files: [])
                    var files: [DocumentImport.File] = []
                    let recognizer = DocumentTextRecognizer()
                    for n in names {
                        let url = dir.appending(path: n)
                        do {
                            var f = try await DocumentsController.read(url, recognizer: recognizer)
                            f.name = n
                            files.append(f)
                        } catch {
                            // One that can't be read leaves the list, with its reason.
                            errors.append(error.localizedDescription)
                            try? FileManager.default.removeItem(at: url)
                        }
                    }
                    if !files.isEmpty {
                        _ = try await DocumentImport.importDocuments(
                            kb: services.knowledgeBase,
                            embed: { text in try await services.embedder.embed(text, catalog: services.catalog) },
                            files: files, collectionName: name, collectionId: id)
                        let added = files.filter { !done.contains($0.name) }.count
                        await MainActor.run { services.vault.record { $0.documents += added } }
                    }
                    Self.record(record, collectionId: files.isEmpty ? nil : id, files: files.map(\.name))
                    return errors
                } catch {
                    errors.append(error.localizedDescription)
                    return errors
                }
            }.value
            importing = false
            job = nil
            errors += newErrors
            reload()
            // Setup ended meanwhile: the copies aren't needed once everything is in.
            if !FileManager.default.fileExists(atPath: AppPaths.setupProgress.path(percentEncoded: false)) && pending.isEmpty {
                try? Self.eraseFolder(services.filesDir)
                reload()
            } else if !pending.isEmpty && newErrors.isEmpty {
                // Files picked during this import.
                importQueued()
            }
        }
    }

    /// Setup is over: what's still waiting goes in now; the folder goes once nothing is left to import.
    func setupEnded() {
        if job == nil && pending.isEmpty {
            try? Self.eraseFolder(services.filesDir)
            reload()
        } else {
            importQueued()
        }
    }
}
