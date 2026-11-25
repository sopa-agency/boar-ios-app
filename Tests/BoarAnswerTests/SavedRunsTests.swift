import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// Android's SavedRunsTest (v2.0.0, t9 0521 items 5 and 8): the saved list (open, delete, kept across a restart and an
/// update), and an old run's export.
struct SavedRunsTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "saved-runs-\(UUID().uuidString)/eval", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ dir: URL, _ name: String, _ text: String) throws { try Data(text.utf8).write(to: dir.appending(path: name)) }

    private func save(_ dir: URL, _ meta: RunMeta, _ rows: [String]) throws {
        try write(dir, "\(meta.runId).jsonl", rows.map { $0 + "\n" }.joined())
        SavedRunStore(dir: dir).writeMeta(meta)
    }

    private func exists(_ dir: URL, _ name: String) -> Bool { FileManager.default.fileExists(atPath: dir.appending(path: name).path(percentEncoded: false)) }

    private let oldRun = "eval-2026-11-01T10-00-00-000Z"
    private var oldRows: [String] {
        [
            #"{"runId":"\#(oldRun)","queryId":"factual-1","modelId":"qwen3-4b-instruct-2507-q4km","outcome":"success","answer":"The capital of Australia is Canberra, \"the capital\"","appVersion":"2.0.0-rc2","createdAt":1761991300000,"retrievedTitles":["Canberra","Australia"]}"#,
            #"{"runId":"\#(oldRun)","queryId":"factual-2","modelId":"qwen3-4b-instruct-2507-q4km","outcome":"success","answer":"Charles Darwin proposed it, and Wallace did too.","appVersion":"2.0.0-rc2","createdAt":1761991400000}"#,
        ]
    }

    @Test func runsAreListedNewestFirstOldOnesFromWhatTheirRowsCarry() throws {
        let dir = try folder()
        try write(dir, "\(oldRun).jsonl", oldRows.joined(separator: "\n"))
        let id = "eval-2026-11-14T05-00-00-000Z"
        try save(dir, RunMeta(runId: id, createdAt: try #require(SavedRunStore.timeOf(id)), appVersion: "2.0.0-rc3", models: ["qwen3-1.7b-q4km"],
                              level: "fast", topics: ["plugins"], source: "request", state: RunMeta.stateDone, rows: 1),
                 [#"{"queryId":"calc-conversion","outcome":"success"}"#])
        let list = SavedRunStore(dir: dir).list()
        #expect(list.map(\.runId) == [id, oldRun])
        let old = list[1]
        #expect(old.createdAt == SavedRunStore.timeOf(oldRun))
        #expect(old.appVersion == "2.0.0-rc2")
        #expect(old.models == ["qwen3-4b-instruct-2507-q4km"])
        #expect(old.level == nil)
        #expect(old.rows == 2)
        #expect(old.state == RunMeta.stateDone)
        #expect(list[0].source == "request")
    }

    @Test func keptAcrossAnAppRestartAndAnUpdateTheFilesAreTheList() throws {
        let dir = try folder()
        let id = "eval-2026-11-14T05-00-00-000Z"
        try save(dir, RunMeta(runId: id, createdAt: 1, appVersion: "2.0.0-rc3", level: "medium", state: RunMeta.stateDone, rows: 1), [#"{"queryId":"a"}"#])
        // A new store on the same folder is the app after a restart, or after an update that kept its data.
        let again = SavedRunStore(dir: URL(filePath: dir.path(percentEncoded: false)))
        #expect(again.list().map(\.runId) == [id])
        #expect(again.readMeta(id)?.level == "medium")
        #expect(again.rows(id).count == 1)
    }

    @Test func openingGivesTheRowsDeletingRemovesTheRunAndOnlyIt() throws {
        let dir = try folder()
        try write(dir, "\(oldRun).jsonl", oldRows.joined(separator: "\n"))
        let id = "eval-2026-11-14T05-00-00-000Z"
        try save(dir, RunMeta(runId: id, createdAt: 2, state: RunMeta.stateDone), [#"{"queryId":"a"}"#])
        try write(dir, "\(id).scorecard.txt", "x")
        let store = SavedRunStore(dir: dir)
        #expect(store.rows(oldRun).map { $0["queryId"]?.stringValue } == ["factual-1", "factual-2"])
        #expect(store.delete(id))
        #expect(store.list().map(\.runId) == [oldRun])
        #expect(!exists(dir, "\(id).meta.json"))
        #expect(!exists(dir, "\(id).scorecard.txt"))
    }

    @Test func aRunTheAppClosedOnIsInterruptedUnlessItIsTheOneGoing() throws {
        let dir = try folder()
        let id = "eval-2026-11-14T05-00-00-000Z"
        try save(dir, RunMeta(runId: id, createdAt: 2), [#"{"queryId":"a"}"#])
        #expect(SavedRunStore(dir: dir).list().map(\.state) == [RunMeta.stateInterrupted])
        #expect(SavedRunStore(dir: dir).list(active: id).map(\.state) == [RunMeta.stateRunning])
    }

    @Test func thePreviousRunIsTheLastFinishedOneOfTheSameLevelAndTopics() throws {
        let dir = try folder()
        try save(dir, RunMeta(runId: "eval-2026-11-10T00-00-00-000Z", createdAt: 10, level: "fast", topics: ["plugins"], state: RunMeta.stateDone), ["{}"])
        try save(dir, RunMeta(runId: "eval-2026-11-11T00-00-00-000Z", createdAt: 20, level: "fast", topics: ["cards"], state: RunMeta.stateDone), ["{}"])
        try save(dir, RunMeta(runId: "eval-2026-11-12T00-00-00-000Z", createdAt: 30, level: "fast", topics: ["plugins"], state: RunMeta.stateFailed), ["{}"])
        let now = RunMeta(runId: "eval-2026-11-13T00-00-00-000Z", createdAt: 40, level: "fast", topics: ["plugins"], state: RunMeta.stateDone)
        try save(dir, now, ["{}"])
        let store = SavedRunStore(dir: dir)
        #expect(store.previous(now)?.runId == "eval-2026-11-10T00-00-00-000Z")
        var byHand = now
        byHand.level = nil
        #expect(store.previous(byHand) == nil)
        #expect(store.lastOfLevel("fast")?.runId == "eval-2026-11-13T00-00-00-000Z")
    }

    @Test func anOldRunExportsAsJsonlAndCsv() throws {
        let dir = try folder()
        try write(dir, "\(oldRun).jsonl", oldRows.joined(separator: "\n"))
        let rows = SavedRunStore(dir: dir).rows(oldRun)
        #expect(EvalExport.jsonl(rows).split(separator: "\n").map { JSONValue(jsonString: String($0)) } == oldRows.map { JSONValue(jsonString: $0) })
        let csv = EvalExport.csv(rows).components(separatedBy: "\n")
        #expect(csv[0] == EvalExport.csvColumns.joined(separator: ","))
        #expect(csv.count == 3)
        #expect(csv[1].contains(#""The capital of Australia is Canberra, ""the capital""""#), "\(csv[1])")
        #expect(csv[1].contains("Canberra|Australia"))
        #expect(csv[1].contains("1761991300000"))
    }

    @Test func scorecardOfAnOldRunOpenedFromTheList() throws {
        let dir = try folder()
        try write(dir, "\(oldRun).jsonl", oldRows.joined(separator: "\n"))
        let card = Scorecard.of(SavedRunStore(dir: dir).rows(oldRun), topics: BenchPresetsTests.topics)
        let core = try #require(card.topics.first)
        #expect(card.topics.count == 1)
        #expect(core.topic == "core")
        // Old rows have no topic: their ids place them in core, whose rules read their text (Canberra, Darwin, English).
        #expect(core.checked == 2)
        #expect(core.passed == 2)
    }

    @Test func aMetaFileReadsAndroidsFieldsWithTheirDefaults() throws {
        let meta = try JSONDecoder().decode(RunMeta.self, from: Data(#"{"runId":"r","createdAt":5}"#.utf8))
        #expect(meta == RunMeta(runId: "r", createdAt: 5))
        #expect(meta.source == "app" && meta.state == RunMeta.stateRunning)
    }
}
