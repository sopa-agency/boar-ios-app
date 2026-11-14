import BoarCore
import BoarModels
import Foundation
import os

/// Model and pack downloads on a background `URLSession`: they keep going while BOAR is in the background or suspended,
/// and the system relaunches the app to finish them (`BoarApp` hands the events over through `.backgroundTask(.urlSession)`).
///
/// Same files and records as `AssetStore.download` (which stays the foreground path for tests and the engine): the file
/// lands at `<filesDir>/<asset.filename>`, its size is checked against the catalog, then `AssetStore.verify` hashes it and
/// writes `integrity.json`. Resumable two ways: the system's resume data of an interrupted task, or an HTTP Range request
/// from a partial file left by an earlier foreground download.
final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "team.sopa.boar.native.assets"
    static let shared = BackgroundDownloads()
    private static let log = BoarLog.logger("downloads")

    struct Progress: Sendable {
        var bytesDone: Int64
        var bytesTotal: Int64
        var verifying: Bool
    }

    private struct Job {
        var asset: CatalogAsset
        var dest: URL
        /// Bytes already in a partial file the Range request continues.
        var rangeStart: Int64
        var onProgress: @Sendable (Progress) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        var finishedFile: Bool
        var failure: Error?
    }

    private let lock = OSAllocatedUnfairLock<[Int: Job]>(initialState: [:])
    private let eventsDone = OSAllocatedUnfairLock<[CheckedContinuation<Void, Never>]>(initialState: [])
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.httpAdditionalHeaders = ["User-Agent": "BOAR-native", "Accept-Encoding": "identity"]
        config.timeoutIntervalForRequest = Double(AssetStore.inactivityTimeoutMs) / 1000
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() { super.init() }

    /// Recreates the session at launch so transfers that finished while the app was gone are delivered.
    func activate() { _ = session }

    /// Called by the scene's `.backgroundTask(.urlSession)`: returns once the system delivered every pending event.
    func handleEvents() async {
        activate()
        await withCheckedContinuation { c in eventsDone.withLock { $0.append(c) } }
    }

    /// Downloads `asset` to its file and verifies it. Throws `AssetStore.DownloadError` like the foreground store.
    /// Cancelling the calling task cancels the transfer and keeps its resume data for the next attempt.
    func download(_ asset: CatalogAsset, store: AssetStore, filesDir: URL, catalog: Catalog, onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        try await DebugLog.download(id: asset.id, sizeBytes: asset.sizeBytes) {
            try await checkedDownload(asset, store: store, filesDir: filesDir, catalog: catalog, onProgress: onProgress)
        }
    }

    private func checkedDownload(_ asset: CatalogAsset, store: AssetStore, filesDir: URL, catalog: Catalog,
                                 onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        if asset.sourceUrl.isEmpty { throw AssetStore.DownloadError.noSource(label: asset.label) }
        guard let url = URL(string: asset.sourceUrl) else { throw AssetStore.DownloadError.noSource(label: asset.label) }
        let dest = filesDir.appending(path: asset.filename)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = Self.size(dest) ?? 0
        if partial > asset.sizeBytes { try? FileManager.default.removeItem(at: dest) }

        let check = StorageBudget.check(StorageBudget.Input(
            usedBytes: store.usedBytes(excluding: [dest.standardizedFileURL.path]),
            reservedBytes: 0, downloadBytes: asset.sizeBytes, alreadyDownloadedBytes: min(partial, asset.sizeBytes),
            freeDiskBytes: DiskSpace.freeBytes(at: filesDir), budgetBytes: catalog.storageBudgetBytes))
        if case .refused(_, _, let message) = check { throw AssetStore.DownloadError.storage(message: message) }

        if partial != asset.sizeBytes {
            try await transfer(asset, url: url, dest: dest, onProgress: onProgress)
        }
        guard Self.size(dest) == asset.sizeBytes else {
            throw AssetStore.DownloadError.paused(label: asset.label, bytesDone: Self.size(dest) ?? 0, idleSeconds: AssetStore.inactivityTimeoutMs / 1000)
        }
        var file = dest
        AppPaths.excludeFromBackup(&file)
        onProgress(Progress(bytesDone: asset.sizeBytes, bytesTotal: asset.sizeBytes, verifying: true))
        let ok = try await Task.detached(priority: .utility) {
            try await store.verify(asset) { p in onProgress(Progress(bytesDone: p.bytesDone, bytesTotal: p.bytesTotal, verifying: true)) }
        }.value
        if !ok {
            store.delete(asset)
            throw AssetStore.DownloadError.checksum(label: asset.label)
        }
        Self.log.info("\(asset.id, privacy: .public): downloaded and verified")
    }

    private func transfer(_ asset: CatalogAsset, url: URL, dest: URL, onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        let resumeFile = AppPaths.resumeDir.appending(path: "\(asset.id).data")
        let existing = await session.allTasks.first { $0.taskDescription == asset.id && $0.state == .running }
        let task: URLSessionTask
        var rangeStart: Int64 = 0
        if let existing {
            // Still running from an earlier launch: attach to it.
            task = existing
            if existing.originalRequest?.value(forHTTPHeaderField: "Range") != nil { rangeStart = Self.size(dest) ?? 0 }
        } else if let data = try? Data(contentsOf: resumeFile) {
            // The resumed transfer continues the request it came from: a Range request appends to the partial file,
            // which is left untouched until a transfer finishes.
            try? FileManager.default.removeItem(at: resumeFile)
            rangeStart = Self.size(dest) ?? 0
            task = session.downloadTask(withResumeData: data)
        } else {
            var request = URLRequest(url: url)
            let partial = Self.size(dest) ?? 0
            if partial > 0 {
                request.setValue("bytes=\(partial)-", forHTTPHeaderField: "Range")
                rangeStart = partial
            }
            task = session.downloadTask(with: request)
        }
        task.taskDescription = asset.id
        let start = rangeStart
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    $0[task.taskIdentifier] = Job(asset: asset, dest: dest, rangeStart: start, onProgress: onProgress, continuation: c, finishedFile: false, failure: nil)
                }
                task.resume()
            }
        } onCancel: {
            if let download = task as? URLSessionDownloadTask {
                download.cancel { data in
                    if let data { try? data.write(to: resumeFile, options: .atomic) }
                }
            } else {
                task.cancel()
            }
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let job = lock.withLock({ $0[downloadTask.taskIdentifier] }) else { return }
        job.onProgress(Progress(bytesDone: job.rangeStart + totalBytesWritten, bytesTotal: job.asset.sizeBytes, verifying: false))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears when this returns: move it now.
        let job = lock.withLock { $0[downloadTask.taskIdentifier] }
        let asset = job?.asset ?? downloadTask.taskDescription.flatMap { id in (try? Catalog.bundled())?.byId(id) }
        guard let asset else { return }
        let dest = job?.dest ?? AppPaths.filesDir.appending(path: asset.filename)
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let fm = FileManager.default
        var failure: Error?
        do {
            if !(200..<300).contains(status) {
                failure = AssetStore.DownloadError.http(label: asset.label, code: status)
            } else if status == 206, let job, job.rangeStart > 0 {
                // A Range continuation: append the new bytes to the partial file.
                let out = try FileHandle(forWritingTo: dest)
                defer { try? out.close() }
                try out.seekToEnd()
                let input = try FileHandle(forReadingFrom: location)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 4 << 20), !chunk.isEmpty { try out.write(contentsOf: chunk) }
            } else {
                if fm.fileExists(atPath: dest.path(percentEncoded: false)) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: location, to: dest)
            }
        } catch {
            failure = AssetStore.DownloadError.storage(message: error.localizedDescription)
        }
        if let size = Self.size(dest), size > asset.sizeBytes {
            try? fm.removeItem(at: dest)
            failure = AssetStore.DownloadError.sizeChanged(label: asset.label, expectedBytes: asset.sizeBytes, serverBytes: size)
        }
        let outcome = failure
        lock.withLock {
            $0[downloadTask.taskIdentifier]?.finishedFile = true
            $0[downloadTask.taskIdentifier]?.failure = outcome
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let job = lock.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        if let error, let id = task.taskDescription {
            let ns = error as NSError
            if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: AppPaths.resumeDir.appending(path: "\(id).data"), options: .atomic)
            }
        }
        guard let job, let c = job.continuation else { return }
        if let failure = job.failure {
            c.resume(throwing: failure)
        } else if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                c.resume(throwing: CancellationError())
            } else if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut {
                c.resume(throwing: AssetStore.DownloadError.paused(label: job.asset.label, bytesDone: Self.size(job.dest) ?? 0, idleSeconds: AssetStore.inactivityTimeoutMs / 1000))
            } else {
                c.resume(throwing: AssetStore.DownloadError.network(error.localizedDescription))
            }
        } else {
            c.resume()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let waiting = eventsDone.withLock { list -> [CheckedContinuation<Void, Never>] in
            defer { list.removeAll() }
            return list
        }
        for c in waiting { c.resume() }
    }

    private static func size(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }
}
