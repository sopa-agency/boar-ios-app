import BoarCore
import Foundation
import Testing
@testable import BoarModels

@Suite struct LoadGuardTests {
    final class Mem: LoadGuard.MarkerStore, @unchecked Sendable {
        private let lock = NSLock()
        private var _v: String?
        var v: String? { get { lock.withLock { _v } } set { lock.withLock { _v = newValue } } }
        func read() -> String? { v }
        func write(_ json: String) { v = json }
        func clear() { v = nil }
    }

    final class L: LoadGuard.Ledger, @unchecked Sendable {
        var crashedIds: [String] = []
        var mappedIds: [String] = []
        var pendingCrash: LoadGuard.Crash?
    }

    let big = LoadGuard.Meta(filename: "models/qwen3-4b.gguf", modelId: "qwen3-4b", label: "Qwen3-4B")
    let small = LoadGuard.Meta(filename: "models/qwen2.5-1.5b.gguf", modelId: "qwen2.5-1.5b", label: "Qwen2.5-1.5B")

    /// A process that starts the load and is killed before it returns; then a new process on the same files.
    func killedDuring(_ store: Mem, _ ledger: L, _ meta: LoadGuard.Meta, repacked: Bool, previous: LoadGuard.Meta? = nil) -> LoadGuard {
        LoadGuard(store: store, ledger: ledger, now: { 1000 }).begin(meta, previous: previous, repacked: repacked)
        return LoadGuard(store: store, ledger: ledger)
    }

    // MARK: LoadGuardTest.kt

    @Test func aLoadThatReturnsAndSettlesLeavesNoMarkerAndNothingBlocked() {
        let store = Mem(), ledger = L()
        let g = LoadGuard(store: store, ledger: ledger)
        g.begin(big, previous: nil, repacked: true)
        g.end(big, loaded: true)
        g.settled("qwen3-4b")
        #expect(store.v == nil)
        #expect(!LoadGuard(store: store, ledger: ledger).isBlocked("qwen3-4b"))
    }

    @Test func killedAfterTheLoadReturnedButBeforeItSettledStillCountsAsALoadKill() {
        let store = Mem(), ledger = L()
        let g = LoadGuard(store: store, ledger: ledger)
        g.begin(big, previous: nil, repacked: true)
        g.end(big, loaded: true)
        // The process dies here (Android F3, Oct 18: 4 s after the load returned).
        let next = LoadGuard(store: store, ledger: ledger)
        #expect(next.isBlocked("qwen3-4b"))
        #expect(next.consume()?.crashedModelId == "qwen3-4b")
    }

    @Test func quittingDuringALoadIsNotALoadKill() {
        let store = Mem(), ledger = L()
        let g = LoadGuard(store: store, ledger: ledger)
        g.begin(big, previous: nil, repacked: true)
        // ⌘Q before the load returned: nothing is resident yet, the marker still goes.
        g.quitting()
        let next = LoadGuard(store: store, ledger: ledger)
        #expect(!next.isBlocked("qwen3-4b"))
        #expect(next.consume() == nil)
    }

    @Test func settlingAnotherModelLeavesTheMarker() {
        let store = Mem(), ledger = L()
        let g = LoadGuard(store: store, ledger: ledger)
        g.begin(big, previous: nil, repacked: true); g.end(big, loaded: true)
        g.settled("qwen2.5-1.5b")
        #expect(LoadGuard(store: store, ledger: ledger).isBlocked("qwen3-4b"))
    }

    @Test func aKilledRepackedLoadBlocksTheModelForAutomaticLoadsAfterOneKill() {
        let store = Mem(), ledger = L()
        let g = killedDuring(store, ledger, big, repacked: true, previous: small)
        #expect(g.isBlocked("qwen3-4b"))
        #expect(!g.mappedNext("qwen3-4b"))
        let crash = g.consume()
        #expect(crash?.crashedModelId == "qwen3-4b")
        #expect(crash?.fallbackLabel == "Qwen2.5-1.5B")
        #expect(g.consume() == nil)
        #expect(store.v == nil)
    }

    @Test func tryAgainWithLessMemoryLoadsTheMappedFileAndKeepsItAfterItWorks() {
        let store = Mem(), ledger = L()
        let g = killedDuring(store, ledger, big, repacked: true)
        g.retryMapped("qwen3-4b")
        #expect(!g.isBlocked("qwen3-4b"))
        #expect(g.mappedNext("qwen3-4b"))
        g.begin(big, previous: nil, repacked: false)
        g.end(big, loaded: true)
        g.settled("qwen3-4b")
        // The next start doesn't go back to the repacked load that closed the app.
        let g2 = LoadGuard(store: store, ledger: ledger)
        #expect(g2.mappedNext("qwen3-4b"))
        #expect(!g2.isBlocked("qwen3-4b"))
    }

    @Test func aKilledMappedLoadIsACrashReportedOnceWithTheFallback() {
        let store = Mem(), ledger = L()
        let g1 = killedDuring(store, ledger, big, repacked: true)
        _ = g1.consume()
        g1.retryMapped("qwen3-4b")
        #expect(g1.mappedNext("qwen3-4b"))
        g1.begin(big, previous: small, repacked: false)
        let g2 = LoadGuard(store: store, ledger: ledger)
        #expect(g2.isBlocked("qwen3-4b"))
        #expect(!g2.mappedNext("qwen3-4b"))
        let crash = g2.consume()
        #expect(crash.map { [$0.crashedModelId, $0.crashedLabel, $0.fallbackModelId, $0.fallbackLabel] } == ["qwen3-4b", "Qwen3-4B", "qwen2.5-1.5b", "Qwen2.5-1.5B"])
        #expect(g2.consume() == nil)
    }

    @Test func ledgerAndMarkerJsonFromTheEarlierVersionStillParse() {
        // A marker written before this change (no "repacked" key: a mapped load) and a crash as settings stored it.
        let store = Mem()
        store.v = #"{"filename":"models/qwen3-4b.gguf","modelId":"qwen3-4b","label":"Qwen3-4B","previous":{"filename":"models/qwen2.5-1.5b.gguf","modelId":"qwen2.5-1.5b","label":"Qwen2.5-1.5B"},"at":1000}"#
        let ledger = L()
        ledger.mappedIds = ["qwen3-4b", "lfm2.5-8b"]
        let g = LoadGuard(store: store, ledger: ledger)
        #expect(g.isBlocked("qwen3-4b"))
        #expect(!g.mappedNext("qwen3-4b"))
        #expect(g.mappedNext("lfm2.5-8b"))
        let stored = LoadGuard.crashFromJson(#"{"crashedModelId":"a","crashedLabel":"A","fallbackModelId":"b","fallbackLabel":"B","at":5,"extra":1}"#)
        #expect(stored == LoadGuard.Crash(crashedModelId: "a", crashedLabel: "A", fallbackModelId: "b", fallbackLabel: "B", at: 5))
        #expect(stored.flatMap { LoadGuard.crashFromJson(LoadGuard.crashToJson($0)) } == stored)
    }

    @Test func theUserPickingTheModelAgainOrALoadThatWorksUnblocksIt() {
        let store = Mem(), ledger = L()
        let g = killedDuring(store, ledger, big, repacked: false)
        #expect(g.isBlocked("qwen3-4b"))
        g.confirm("qwen3-4b")
        #expect(!g.isBlocked("qwen3-4b"))
        ledger.crashedIds = ["qwen3-4b"]
        g.begin(big, previous: nil, repacked: true); g.end(big, loaded: true); g.settled("qwen3-4b")
        #expect(!g.isBlocked("qwen3-4b"))
    }

    @Test func pickingItAgainInModelsUnblocksItAfterARepackedKill() {
        let store = Mem(), ledger = L()
        let g = killedDuring(store, ledger, big, repacked: true)
        #expect(g.isBlocked("qwen3-4b"))
        g.confirm("qwen3-4b")
        #expect(!g.isBlocked("qwen3-4b"))
        #expect(!LoadGuard(store: store, ledger: ledger).isBlocked("qwen3-4b"))
    }

    @Test func aFailedLoadReturnedNotKilledIsNeitherACrashNorAMappedRetry() {
        let store = Mem(), ledger = L()
        let g = LoadGuard(store: store, ledger: ledger)
        g.begin(big, previous: nil, repacked: true); g.end(big, loaded: false)
        let g2 = LoadGuard(store: store, ledger: ledger)
        #expect(!g2.isBlocked("qwen3-4b")); #expect(!g2.mappedNext("qwen3-4b"))
    }

    @Test func anUnreadableMarkerIsDropped() {
        let store = Mem(); store.v = "{not json"
        let g = LoadGuard(store: store, ledger: L())
        #expect(!g.isBlocked("qwen3-4b"))
        #expect(store.v == nil)
    }

    /// Android issue #89 (an exit the system records as the user's isn't a load kill); iOS has no such record, so the hook
    /// stays off and every leftover marker counts.
    @Test func anExitKnownNotToBeALoadKillClearsTheMarkerWithoutBlocking() {
        let store = Mem(), ledger = L()
        LoadGuard(store: store, ledger: ledger, now: { 1000 }).begin(big, previous: small, repacked: true)
        let g = LoadGuard(store: store, ledger: ledger)
        g.exitWasNotLoadKill = { $0 == 1000 }
        #expect(!g.isBlocked("qwen3-4b"))
        #expect(g.consume() == nil)
        #expect(store.v == nil)
    }

    @Test func anUnknownExitStillCountsAsALoadKill() {
        let store = Mem(), ledger = L()
        let g = killedDuring(store, ledger, big, repacked: true, previous: small)
        #expect(g.isBlocked("qwen3-4b"))
        #expect(g.consume()?.crashedModelId == "qwen3-4b")
    }

    @Test func aStallIsUnder1TokPerSForAtLeast10SOfWriting() {
        #expect(LoadGuard.isDecodeStall(generatedTokens: 5, decodeMs: 12_000))
        #expect(!LoadGuard.isDecodeStall(generatedTokens: 5, decodeMs: 9_000)) // too short to tell
        #expect(!LoadGuard.isDecodeStall(generatedTokens: 12, decodeMs: 10_000)) // 1.2 tok/s
        #expect(LoadGuard.isDecodeStall(generatedTokens: 0, decodeMs: 10_000))
    }

    // MARK: Swift-side adapters

    @Test func theMarkerAndCrashRecordsKeepTheKotlinFieldNames() throws {
        let store = Mem()
        let g = LoadGuard(store: store, ledger: L(), now: { 42 })
        g.begin(big, previous: small, repacked: true)
        let obj = try #require(JSONValue(jsonString: store.v ?? ""))
        #expect(obj["filename"]?.stringValue == "models/qwen3-4b.gguf")
        #expect(obj["modelId"]?.stringValue == "qwen3-4b")
        #expect(obj["previous"]?["modelId"]?.stringValue == "qwen2.5-1.5b")
        #expect(obj["at"]?.int64Value == 42)
        #expect(obj["repacked"]?.boolValue == true)
        // An Expo/Android-written marker without the optional keys still reads.
        let m = try JSONDecoder().decode(LoadGuard.Marker.self, from: Data(#"{"filename":"models/x.gguf","at":7}"#.utf8))
        #expect(m == LoadGuard.Marker(filename: "models/x.gguf", at: 7))
        let c = LoadGuard.Crash(crashedModelId: "a", crashedLabel: "A", fallbackModelId: "b", fallbackLabel: "B", at: 9)
        #expect(LoadGuard.crashFromJson(LoadGuard.crashToJson(c)) == c)
        #expect(LoadGuard.crashFromJson("nope") == nil)
    }

    @Test func settingsLedgerPersistsInTheExpoKeys() {
        let kv = InMemoryKeyValueStore()
        let settings = AppSettings(store: kv)
        let store = Mem()
        let g1 = LoadGuard(store: store, ledger: SettingsLoadLedger(settings: settings), now: { 5 })
        g1.begin(big, previous: small, repacked: false)
        // New process: marker file and settings survive.
        let g2 = LoadGuard(store: store, ledger: SettingsLoadLedger(settings: AppSettings(store: kv)))
        #expect(g2.isBlocked("qwen3-4b"))
        #expect(settings.loadCrashedIds == ["qwen3-4b"])
        #expect(settings.pendingLoadCrash?["fallbackLabel"]?.stringValue == "Qwen2.5-1.5B")
        #expect(g2.consume()?.at == 5)
        #expect(settings.pendingLoadCrash == nil)
        g2.confirm("qwen3-4b")
        #expect(settings.loadCrashedIds.isEmpty && settings.raw()["loadCrashedIds"] == nil)
    }

    @Test func fileMarkerStoreWritesReadsAndClears() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("boar-marker-\(UUID().uuidString)/nested/load-marker.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let s = FileMarkerStore(url: url)
        #expect(s.read() == nil)
        s.write("{\"a\":1}")
        #expect(s.read() == "{\"a\":1}")
        s.clear()
        #expect(s.read() == nil)
    }
}
