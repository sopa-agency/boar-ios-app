import CryptoKit
import Foundation
import Testing
@testable import BoarModels

/// Downloads against a local HTTP server: fresh, resumed, Range ignored, size changed, bad checksum.
@Suite(.serialized) struct AssetStoreTests {
    static let payload = seededBytes(3_000_000, seed: 7)
    static let sha = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

    struct Env {
        let server: TestHTTPServer
        let dir: URL

        init() throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("boar-assets-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            server = TestHTTPServer(served: AssetStoreTests.payload)
            server.start()
        }

        func finish() {
            server.stop()
            try? FileManager.default.removeItem(at: dir)
        }

        func asset(size: Int64 = Int64(AssetStoreTests.payload.count), digest: String = AssetStoreTests.sha) -> CatalogAsset {
            CatalogAsset(
                id: "m", kind: .llm, label: "Test model", filename: "models/m.gguf", sizeBytes: size, sha256: digest,
                sourceUrl: "http://127.0.0.1:\(server.port)/m.gguf", license: "MIT", description: "", required: false, answerTier: .compact)
        }

        func store(_ a: CatalogAsset, networkAllowed: Bool = true) -> AssetStore {
            AssetStore(filesDir: dir, catalog: Catalog(storageBudgetBytes: 50_000_000_000, ramBudgetBytes: 12 << 30, models: [a], tiers: []), networkAllowed: networkAllowed)
        }

        func writePartial(_ s: AssetStore, _ a: CatalogAsset, _ bytes: [UInt8]) throws {
            let f = s.fileURL(of: a)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes).write(to: f)
        }
    }

    @Test func downloadsVerifiesAndRecordsTheFile() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(); let s = env.store(a)
        try await s.download(a)
        #expect(try Data(contentsOf: s.fileURL(of: a)) == Data(Self.payload))
        #expect(s.status(a).checksumOk == true)
        #expect(try String(contentsOf: env.dir.appendingPathComponent("integrity.json"), encoding: .utf8).contains("models/m.gguf"))
    }

    @Test func resumesAPartialFileWithARangeRequest() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(); let s = env.store(a)
        try env.writePartial(s, a, Array(Self.payload.prefix(1_000_000)))
        #expect(s.status(a).partialBytes == 1_000_000)
        try await s.download(a)
        #expect(env.server.requests == ["bytes=1000000-"])
        #expect(try Data(contentsOf: s.fileURL(of: a)) == Data(Self.payload))
        #expect(s.status(a).checksumOk == true)
    }

    @Test func startsOverWhenTheServerIgnoresRange() async throws {
        let env = try Env(); defer { env.finish() }
        env.server.honorRange = false
        let a = env.asset(); let s = env.store(a)
        try env.writePartial(s, a, Array(Self.payload.prefix(1_000_000)))
        try await s.download(a)
        #expect(try Data(contentsOf: s.fileURL(of: a)) == Data(Self.payload))
        #expect(s.status(a).checksumOk == true)
    }

    @Test func refusesAFileWhoseSizeOnTheServerChanged() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(size: Int64(Self.payload.count) + 10)
        do {
            try await env.store(a).download(a)
            Issue.record("expected sizeChanged")
        } catch let e as AssetStore.DownloadError {
            #expect(e == .sizeChanged(label: "Test model", expectedBytes: Int64(Self.payload.count) + 10, serverBytes: Int64(Self.payload.count)))
            #expect(e.message.contains("now serves 3000000 bytes"))
        }
    }

    @Test func restartsFromZeroWhenAResumedPartialIsOfAnotherFile() async throws {
        let env = try Env(); defer { env.finish() }
        // The ranged answer claims another total: the partial bytes belong to a different file, so the store starts over.
        env.server.rangeTotalOverride = Self.payload.count + 7
        let a = env.asset(); let s = env.store(a)
        try env.writePartial(s, a, Array(repeating: 9, count: 1_000))
        try await s.download(a)
        #expect(env.server.requests == ["bytes=1000-", nil])
        #expect(try Data(contentsOf: s.fileURL(of: a)) == Data(Self.payload))
        #expect(s.status(a).checksumOk == true)
    }

    @Test func deletesADownloadThatFailsItsChecksum() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(digest: String(repeating: "0", count: 64)); let s = env.store(a)
        do {
            try await s.download(a)
            Issue.record("expected checksum")
        } catch let e as AssetStore.DownloadError {
            #expect(e == .checksum(label: "Test model"))
        }
        #expect(!FileManager.default.fileExists(atPath: s.fileURL(of: a).path))
        #expect(!s.status(a).present)
    }

    @Test func readsIntegrityRecordsWrittenByTheExpoApp_mtimeInSeconds() throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(); let s = env.store(a)
        try env.writePartial(s, a, Self.payload)
        let f = s.fileURL(of: a)
        let mtime = Double(AssetStore.lastModifiedMillis(f)!) / 1000.0
        try #"{"models/m.gguf":{"size":\#(Self.payload.count),"mtime":\#(mtime),"sha256":"\#(Self.sha)"}}"#
            .write(to: env.dir.appendingPathComponent("integrity.json"), atomically: true, encoding: .utf8)
        #expect(s.status(a).checksumOk == true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: mtime + 5)], ofItemAtPath: f.path)
        #expect(s.status(a).checksumOk == nil)
    }

    @Test func verifyRecordsAMatchAndForgetsAMismatch() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(); let s = env.store(a)
        try env.writePartial(s, a, Self.payload)
        #expect(s.status(a).present && s.status(a).checksumOk == nil)
        #expect(try await s.verify(a) == true)
        #expect(s.status(a).checksumOk == true)
        let bad = env.asset(digest: String(repeating: "f", count: 64))
        #expect(try await s.verify(bad) == false)
        #expect(s.status(bad).checksumOk == nil)
    }

    @Test func anOversizedFileIsDeletedAndASmallerOneIsTheResumePoint() throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(); let s = env.store(a)
        try env.writePartial(s, a, Self.payload + [0])
        let st = s.status(a)
        #expect(!st.present && st.partialBytes == 0)
        #expect(!FileManager.default.fileExists(atPath: s.fileURL(of: a).path))
    }

    @Test func refusesWithoutASourceOrWithoutTheNetwork() async throws {
        let env = try Env(); defer { env.finish() }
        var a = env.asset(); a.sourceUrl = ""
        await #expect(throws: AssetStore.DownloadError.noSource(label: "Test model")) { try await env.store(a).download(a) }
        let b = env.asset()
        await #expect(throws: AssetStore.DownloadError.offlineBuild) { try await env.store(b, networkAllowed: false).download(b) }
        #expect(env.server.requests.isEmpty)
    }

    @Test func refusesADownloadOverTheStorageBudget() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset()
        let s = AssetStore(filesDir: env.dir, catalog: Catalog(storageBudgetBytes: 1_000_000_000, ramBudgetBytes: 0, models: [a], tiers: []))
        do {
            try await s.download(a)
            Issue.record("expected storage")
        } catch let e as AssetStore.DownloadError {
            guard case .storage(let message) = e else { Issue.record("wrong error \(e)"); return }
            #expect(message.contains("storage budget"))
        }
    }

    @Test func aCancelledDownloadLeavesThePartialFileAndResumes() async throws {
        let env = try Env(); defer { env.finish() }
        let a = env.asset(); let s = env.store(a)
        let task = Task { try await s.download(a) }
        task.cancel()
        _ = try? await task.value
        // Whatever arrived stays as the resume point (possibly nothing); a new attempt completes the file.
        try await s.download(a)
        #expect(s.status(a).checksumOk == true)
        #expect(try Data(contentsOf: s.fileURL(of: a)) == Data(Self.payload))
    }

    @Test func requiredPresentNeedsEveryRequiredAssetAndOneSetupModel() throws {
        let env = try Env(); defer { env.finish() }
        let emb = CatalogAsset(id: "e", kind: .embedding, label: "e", filename: "models/e.gguf", sizeBytes: 4, sha256: "", sourceUrl: "", license: "", description: "", required: true)
        let llm = CatalogAsset(id: "l", kind: .llm, label: "l", filename: "models/l.gguf", sizeBytes: 3, sha256: "", sourceUrl: "", license: "", description: "", required: false, answerTier: .compact)
        let s = AssetStore(filesDir: env.dir, catalog: Catalog(storageBudgetBytes: 1 << 40, ramBudgetBytes: 0, models: [emb, llm], tiers: []))
        #expect(!s.requiredPresent())
        try env.writePartial(s, emb, [1, 2, 3, 4])
        #expect(!s.requiredPresent())
        try env.writePartial(s, llm, [1, 2, 3])
        #expect(s.requiredPresent())
        #expect(s.usedBytes() == 7)
        #expect(s.usedBytes(excluding: [s.fileURL(of: llm).standardizedFileURL.path]) == 4)
    }
}
