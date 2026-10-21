import BoarCore
import CryptoKit
import Foundation

/// Installed assets on disk: status, sha256 verification and resumable downloads (port of `AssetStore.kt`, itself
/// src/models/ModelManager.ts).
///
/// Same layout and records as the Expo and Android apps, so an upgrade keeps everything: assets live at
/// `<filesDir>/<asset.filename>` and verified files are listed in `<filesDir>/integrity.json` as
/// `{filename: {size, mtime (seconds, as Expo reported it), sha256}}`.
///
/// iOS mapping: `HttpURLConnection` becomes a foreground `URLSession` data task whose delegate writes and hashes each chunk as
/// it arrives (no byte is read twice); `coroutineContext.ensureActive` becomes Swift task cancellation (the partial file stays
/// as the resume point). Downloaded files are flagged "excluded from backup".
public final class AssetStore: @unchecked Sendable {
    public struct Status: Sendable, Equatable {
        public var asset: CatalogAsset
        public var present: Bool
        public var sizeOnDiskBytes: Int64
        /// true = sha256 verified on this phone for this exact file; nil = not checked yet.
        public var checksumOk: Bool?
        /// Bytes of an interrupted download, the resume point.
        public var partialBytes: Int64

        public init(asset: CatalogAsset, present: Bool, sizeOnDiskBytes: Int64, checksumOk: Bool?, partialBytes: Int64 = 0) {
            self.asset = asset; self.present = present; self.sizeOnDiskBytes = sizeOnDiskBytes
            self.checksumOk = checksumOk; self.partialBytes = partialBytes
        }
    }

    public struct Progress: Sendable, Equatable {
        public enum Phase: Sendable { case downloading, verifying }
        public var bytesDone: Int64
        public var bytesTotal: Int64
        public var phase: Phase

        public init(bytesDone: Int64, bytesTotal: Int64, phase: Phase) {
            self.bytesDone = bytesDone; self.bytesTotal = bytesTotal; self.phase = phase
        }
    }

    /// Why a download didn't finish. `message` is what the UI shows.
    public enum DownloadError: Error, Equatable, LocalizedError, Sendable {
        case noSource(label: String)
        case offlineBuild
        case storage(message: String)
        case sizeChanged(label: String, expectedBytes: Int64, serverBytes: Int64)
        case paused(label: String, bytesDone: Int64, idleSeconds: Int)
        case checksum(label: String)
        case http(label: String, code: Int)
        /// Any other transport failure (Kotlin: a bare `IOException`).
        case network(String)

        public var message: String {
            switch self {
            case .noSource(let label): return "\(label) isn't available for download yet. Import the file instead."
            case .offlineBuild: return "This build of BOAR has no network permission. Import the file instead."
            case .storage(let message): return message
            case .sizeChanged(let label, let expected, let server):
                return "The download server now serves \(server) bytes for \(label), not the \(expected) this version of BOAR expects. " +
                    "Skip it for now, import the file, or update the app."
            case .paused(let label, _, let idle):
                return "Download of \(label) paused (no data for \(idle)s). Tap Retry to resume, or check your connection."
            case .checksum(let label): return "\(label) didn't match its checksum and was removed. Retry the download."
            case .http(let label, let code): return "The server answered \(code) for \(label). Retry later."
            case .network(let message): return message
            }
        }

        public var errorDescription: String? { message }
    }

    /// No bytes for this long pauses a download (the partial file stays for the next attempt).
    public static let inactivityTimeoutMs = 60_000
    private static let storageDirs = ["models/", "corpus/", "poi/", "SQLite/"]

    private let filesDir: URL
    private let catalog: Catalog
    /// False in a build without network access (the offline variant).
    private let networkAllowed: Bool
    private let sessionConfiguration: URLSessionConfiguration
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var activeDownloads: [String: CatalogAsset] = [:]

    public init(
        filesDir: URL, catalog: Catalog, networkAllowed: Bool = true,
        sessionConfiguration: URLSessionConfiguration = .ephemeral, log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.filesDir = filesDir
        self.catalog = catalog
        self.networkAllowed = networkAllowed
        self.sessionConfiguration = sessionConfiguration
        self.log = log
    }

    public func fileURL(of asset: CatalogAsset) -> URL { filesDir.appendingPathComponent(asset.filename) }

    private var integrityFile: URL { filesDir.appendingPathComponent("integrity.json") }

    // MARK: status

    public func status(_ asset: CatalogAsset) -> Status {
        let f = fileURL(of: asset)
        guard let size = Self.fileSize(f) else { return Status(asset: asset, present: false, sizeOnDiskBytes: 0, checksumOk: nil) }
        if size != asset.sizeBytes {
            // Smaller = an interrupted download, kept as the resume point. Larger can't be a prefix: delete it.
            let active = lock.withLock { activeDownloads[asset.id] != nil }
            if size < asset.sizeBytes || active {
                return Status(asset: asset, present: false, sizeOnDiskBytes: 0, checksumOk: nil, partialBytes: size)
            }
            log("\(asset.id): deleting oversized file (\(size) > \(asset.sizeBytes))")
            try? FileManager.default.removeItem(at: f)
            return Status(asset: asset, present: false, sizeOnDiskBytes: 0, checksumOk: nil)
        }
        let rec = loadVerified()[asset.filename]
        let verified = rec != nil && rec!.size == size && Self.sameMtime(rec!.mtime, f) && rec!.sha256.lowercased() == asset.sha256.lowercased()
        return Status(asset: asset, present: true, sizeOnDiskBytes: size, checksumOk: verified ? true : nil)
    }

    public func statusAll() -> [Status] { catalog.models.map(status) }

    /// Setup is complete: every required asset plus one model setup offers on disk with the right size.
    public func requiredPresent() -> Bool {
        catalog.models.filter(\.required).allSatisfy { status($0).present } && catalog.setupModels.contains { status($0).present }
    }

    // MARK: verify

    /// Streams the installed file through SHA-256 and remembers a match.
    public func verify(_ asset: CatalogAsset, onProgress: @Sendable (Progress) -> Void = { _ in }) async throws -> Bool {
        if asset.sha256.isEmpty { return true }
        let f = fileURL(of: asset)
        guard let size = Self.fileSize(f) else { throw CocoaError(.fileNoSuchFile) }
        var hasher = SHA256()
        try Self.hashInto(&hasher, f, bytes: size) { done in onProgress(Progress(bytesDone: done, bytesTotal: size, phase: .verifying)) }
        let ok = Self.hex(hasher.finalize()) == asset.sha256.lowercased()
        if ok { recordVerified(asset) } else { forgetVerified(asset) }
        log("\(asset.id): sha256 \(ok ? "ok" : "MISMATCH")")
        return ok
    }

    // MARK: download

    /// Downloads `asset` to its file, resuming from a partial one with an HTTP Range request. The sha256 is computed while the
    /// bytes arrive (the partial part first), so nothing is read twice. A stall of `inactivityTimeoutMs` or a cancelled task
    /// leaves the partial file for the next attempt.
    public func download(_ asset: CatalogAsset, onProgress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws {
        if asset.sourceUrl.isEmpty { throw DownloadError.noSource(label: asset.label) }
        if !networkAllowed { throw DownloadError.offlineBuild }
        let dest = fileURL(of: asset)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let others = lock.withLock { activeDownloads.values.filter { $0.id != asset.id } }
        let partialBytes = Self.fileSize(dest) ?? 0
        let excluded = Set(([dest] + others.map { fileURL(of: $0) }).map { $0.standardizedFileURL.path })
        let check = StorageBudget.check(StorageBudget.Input(
            usedBytes: usedBytes(excluding: excluded),
            reservedBytes: others.reduce(0) { $0 + $1.sizeBytes },
            downloadBytes: asset.sizeBytes,
            alreadyDownloadedBytes: partialBytes,
            freeDiskBytes: DiskSpace.freeBytes(at: filesDir),
            budgetBytes: catalog.storageBudgetBytes))
        if case .refused(_, _, let message) = check { throw DownloadError.storage(message: message) }

        if partialBytes == asset.sizeBytes {
            log("\(asset.id): complete file already on disk, verifying instead of downloading")
            if try await !verify(asset, onProgress: onProgress) {
                try? FileManager.default.removeItem(at: dest)
                throw DownloadError.checksum(label: asset.label)
            }
            return
        }
        if partialBytes > asset.sizeBytes { try? FileManager.default.removeItem(at: dest) }

        lock.withLock { activeDownloads[asset.id] = asset }
        defer { lock.withLock { activeDownloads[asset.id] = nil } }
        try await transfer(asset, dest: dest, onProgress: onProgress)
    }

    private func transfer(_ asset: CatalogAsset, dest: URL, onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        var hasher = SHA256()
        var resumeFrom = Self.fileSize(dest) ?? 0
        if resumeFrom > 0 { try Self.hashInto(&hasher, dest, bytes: resumeFrom) { _ in } }

        for attempt in 0...1 {
            guard let url = URL(string: asset.sourceUrl) else { throw DownloadError.noSource(label: asset.label) }
            var request = URLRequest(url: url)
            request.setValue("BOAR-native", forHTTPHeaderField: "User-Agent")
            // A gzip'd body would make the byte counts and the hash differ from the file.
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if resumeFrom > 0 { request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range") }

            let t = Transfer(asset: asset, dest: dest, resumeFrom: resumeFrom, hasher: hasher, log: log, onProgress: onProgress)
            let outcome = try await t.run(request, configuration: sessionConfiguration)
            if outcome == .restart, attempt == 0 {
                // A mismatch on a resumed request means the partial bytes are of another file: start over from zero.
                resumeFrom = 0
                hasher = SHA256()
                continue
            }
            onProgress(Progress(bytesDone: t.done, bytesTotal: asset.sizeBytes, phase: .downloading))
            if t.done != asset.sizeBytes { throw DownloadError.paused(label: asset.label, bytesDone: t.done, idleSeconds: Self.inactivityTimeoutMs / 1000) }
            let ok = asset.sha256.isEmpty || Self.hex(t.hasher.finalize()) == asset.sha256.lowercased()
            if !ok {
                try? FileManager.default.removeItem(at: dest)
                forgetVerified(asset)
                throw DownloadError.checksum(label: asset.label)
            }
            recordVerified(asset)
            log("\(asset.id): downloaded and verified (\(t.done) bytes)")
            return
        }
    }

    public func delete(_ asset: CatalogAsset) {
        try? FileManager.default.removeItem(at: fileURL(of: asset))
        forgetVerified(asset)
    }

    /// Bytes BOAR's assets use on disk, excluding `excluding` (standardized paths: partial downloads in flight).
    public func usedBytes(excluding: Set<String> = []) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for dir in Self.storageDirs {
            let root = filesDir.appendingPathComponent(dir)
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            for case let u as URL in e {
                guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
                if excluding.contains(u.standardizedFileURL.path) { continue }
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }

    // MARK: integrity.json, shared with the Expo app's format

    private struct VerifiedRecord: Codable {
        var size: Int64
        var mtime: Double
        var sha256: String
    }

    private func loadVerified() -> [String: VerifiedRecord] {
        lock.withLock {
            guard let data = try? Data(contentsOf: integrityFile), let r = try? JSONDecoder().decode([String: VerifiedRecord].self, from: data) else { return [:] }
            return r
        }
    }

    private func saveVerified(_ records: [String: VerifiedRecord]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(records) { try? data.write(to: integrityFile, options: .atomic) }
    }

    private func recordVerified(_ asset: CatalogAsset) {
        let f = fileURL(of: asset)
        guard let size = Self.fileSize(f), let ms = Self.lastModifiedMillis(f) else { return }
        lock.withLock {
            var records = (try? Data(contentsOf: integrityFile)).flatMap { try? JSONDecoder().decode([String: VerifiedRecord].self, from: $0) } ?? [:]
            records[asset.filename] = VerifiedRecord(size: size, mtime: Double(ms) / 1000.0, sha256: asset.sha256)
            saveVerified(records)
        }
    }

    private func forgetVerified(_ asset: CatalogAsset) {
        lock.withLock {
            var records = (try? Data(contentsOf: integrityFile)).flatMap { try? JSONDecoder().decode([String: VerifiedRecord].self, from: $0) } ?? [:]
            if records.removeValue(forKey: asset.filename) != nil { saveVerified(records) }
        }
    }

    // MARK: file helpers

    static func fileSize(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), (attrs[.type] as? FileAttributeType) == .typeRegular else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    /// `File.lastModified()`: milliseconds, truncated.
    static func lastModifiedMillis(_ url: URL) -> Int64? {
        guard let d = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
        return Int64((d.timeIntervalSince1970 * 1000).rounded(.down))
    }

    private static func sameMtime(_ seconds: Double, _ f: URL) -> Bool {
        guard let ms = lastModifiedMillis(f) else { return false }
        return abs(seconds - Double(ms) / 1000.0) < 0.002
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    private static func hashInto(_ hasher: inout SHA256, _ url: URL, bytes: Int64, onChunk: (Int64) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var left = bytes
        var done: Int64 = 0
        while left > 0 {
            try Task.checkCancellation()
            let want = Int(min(Int64(1 << 20), left))
            guard let chunk = try handle.read(upToCount: want), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            left -= Int64(chunk.count)
            done += Int64(chunk.count)
            onChunk(done)
        }
    }
}

// MARK: - One HTTP transfer

/// A single request streamed to the asset file: the delegate (a serial queue) writes and hashes every chunk.
private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Outcome { case completed, restart }

    let asset: CatalogAsset
    let dest: URL
    private(set) var hasher: SHA256
    private(set) var done: Int64
    private var resumeFrom: Int64
    private let log: @Sendable (String) -> Void
    private let onProgress: @Sendable (AssetStore.Progress) -> Void

    private var handle: FileHandle?
    private var failure: Error?
    private var restartRequested = false
    private var lastReport = Date.distantPast

    private let stateLock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelRequested = false
    private var continuation: CheckedContinuation<Outcome, Error>?

    init(asset: CatalogAsset, dest: URL, resumeFrom: Int64, hasher: SHA256, log: @escaping @Sendable (String) -> Void, onProgress: @escaping @Sendable (AssetStore.Progress) -> Void) {
        self.asset = asset
        self.dest = dest
        self.resumeFrom = resumeFrom
        self.done = resumeFrom
        self.hasher = hasher
        self.log = log
        self.onProgress = onProgress
    }

    func run(_ request: URLRequest, configuration base: URLSessionConfiguration) async throws -> Outcome {
        let config = base.copy() as! URLSessionConfiguration
        // timeoutIntervalForRequest restarts with every packet: it is the inactivity timeout.
        config.timeoutIntervalForRequest = TimeInterval(AssetStore.inactivityTimeoutMs / 1000)
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Outcome, Error>) in
                let t = session.dataTask(with: request)
                stateLock.lock()
                continuation = cont
                task = t
                let cancelled = cancelRequested
                stateLock.unlock()
                if cancelled { t.cancel() }
                t.resume()
            }
        } onCancel: {
            stateLock.lock()
            cancelRequested = true
            let t = task
            stateLock.unlock()
            t?.cancel()
        }
    }

    // MARK: delegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            try begin(response)
            completionHandler(restartRequested ? .cancel : .allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, let handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = AssetStore.DownloadError.network("Couldn't write \(asset.label): \(error.localizedDescription)")
            dataTask.cancel()
            return
        }
        hasher.update(data: data)
        done += Int64(data.count)
        let now = Date()
        if now.timeIntervalSince(lastReport) > 0.25 {
            lastReport = now
            onProgress(AssetStore.Progress(bytesDone: done, bytesTotal: asset.sizeBytes, phase: .downloading))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        stateLock.lock()
        let cont = continuation
        continuation = nil
        let cancelled = cancelRequested
        stateLock.unlock()
        guard let cont else { return }
        if let failure { cont.resume(throwing: failure); return }
        if restartRequested { cont.resume(returning: .restart); return }
        if cancelled { cont.resume(throwing: CancellationError()); return }
        if let error {
            if (error as? URLError)?.code == .timedOut {
                cont.resume(throwing: AssetStore.DownloadError.paused(label: asset.label, bytesDone: done, idleSeconds: AssetStore.inactivityTimeoutMs / 1000))
            } else {
                cont.resume(throwing: AssetStore.DownloadError.network(error.localizedDescription))
            }
            return
        }
        cont.resume(returning: .completed)
    }

    // MARK: response handling

    private func begin(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AssetStore.DownloadError.network("Not an HTTP response for \(asset.label).") }
        let code = http.statusCode
        if code != 200 && code != 206 { throw AssetStore.DownloadError.http(label: asset.label, code: code) }
        if resumeFrom > 0 && code == 200 {
            // The server ignored Range and sends the whole file: take it from zero rather than append it.
            log("\(asset.id): Range ignored, restarting from zero")
            truncateDest()
            hasher = SHA256()
            resumeFrom = 0
            done = 0
        }
        let length = http.expectedContentLength
        var total: Int64 = -1
        if code == 206 {
            if let t = Self.contentRangeTotal(http) { total = t } else if length >= 0 { total = resumeFrom + length }
        } else {
            total = length
        }
        if total > 0 && total != asset.sizeBytes {
            if resumeFrom > 0 {
                // A mismatch on a resumed request means the partial bytes are of another file: start over.
                truncateDest()
                done = 0
                restartRequested = true
                return
            }
            throw AssetStore.DownloadError.sizeChanged(label: asset.label, expectedBytes: asset.sizeBytes, serverBytes: total)
        }
        try openDest(append: resumeFrom > 0)
    }

    private func truncateDest() {
        if let h = try? FileHandle(forWritingTo: dest) {
            try? h.truncate(atOffset: 0)
            try? h.close()
        }
    }

    private func openDest(append: Bool) throws {
        do {
            if !append || !FileManager.default.fileExists(atPath: dest.path) { FileManager.default.createFile(atPath: dest.path, contents: nil) }
            let h = try FileHandle(forWritingTo: dest)
            if append { try h.seekToEnd() } else { try h.truncate(atOffset: 0) }
            handle = h
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var d = dest
            try? d.setResourceValues(values)
        } catch {
            throw AssetStore.DownloadError.network("Couldn't open \(asset.label) for writing: \(error.localizedDescription)")
        }
    }

    private static func contentRangeTotal(_ http: HTTPURLResponse) -> Int64? {
        guard let v = http.value(forHTTPHeaderField: "Content-Range"), let slash = v.lastIndex(of: "/") else { return nil }
        return Int64(v[v.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }
}
