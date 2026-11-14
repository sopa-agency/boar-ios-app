import Foundation
import Testing

@testable import BoarCore

struct DebugLogFileTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "debuglog-\(UUID().uuidString)")
    }

    @Test func aLineHasTheTimeTheNameAndOnlyTheFieldsWithAValue() {
        let date = Date(timeIntervalSince1970: 1_794_600_000.25)
        let line = DebugLogFile.line("model.load", [("id", "qwen3"), ("ok", true), ("ms", 812), ("error", nil), ("why", "low  memory\nnow")], at: date)
        #expect(line.hasSuffix(" model.load id=qwen3 ok=true ms=812 why=low_memory_now\n"))
        let time = String(line.split(separator: " ")[0])
        #expect(time.contains("T") && time.contains(".250"))
        #expect(!line.contains("error="))
    }

    @Test func appendsInOrderAndSavesTheHeaderFirst() throws {
        let log = DebugLogFile(dir: tempDir())
        log.append("a\n")
        log.append("b\n")
        log.flush()
        #expect(String(decoding: log.contents(header: "# h\n"), as: UTF8.self) == "# h\na\nb\n")
        #expect(log.sizeBytes() == 4)
    }

    @Test func pastTheLimitTheFileRollsOverAndTheOldestIsDropped() {
        let log = DebugLogFile(dir: tempDir(), maxBytes: 9)
        for line in ["one-12345\n", "two-12345\n", "three-123\n", "four-1234\n"] { log.append(line) }
        log.flush()
        // Each write onto a file past 9 bytes moves the current file aside: "one" and "two" are gone, "three" is the older file.
        #expect(String(decoding: log.contents(header: ""), as: UTF8.self) == "three-123\nfour-1234\n")
    }

    @Test func clearRemovesBothFiles() {
        let log = DebugLogFile(dir: tempDir(), maxBytes: 4)
        log.append("12345\n")
        log.append("6\n")
        log.flush()
        #expect(log.sizeBytes() > 0)
        log.clear()
        #expect(log.sizeBytes() == 0)
        #expect(log.contents(header: "").isEmpty)
    }
}
