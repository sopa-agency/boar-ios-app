import Foundation

/// The debug log's files (android DebugLog's storage): one line per record, appended to `boar-debug.log`; past `maxBytes`
/// it becomes `boar-debug.1.log`, the older one dropped, so the log stays under twice that. Writes go through one serial
/// queue, in order. Holds only what the app passes in (numbers and ids, never what was asked or answered).
public final class DebugLogFile: Sendable {
    public static let defaultMaxBytes: Int64 = 2 * 1024 * 1024

    public let dir: URL
    public let maxBytes: Int64
    private let queue = DispatchQueue(label: "team.sopa.boar.debuglog", qos: .utility)

    public var current: URL { dir.appending(path: "boar-debug.log") }
    public var previous: URL { dir.appending(path: "boar-debug.1.log") }

    public init(dir: URL, maxBytes: Int64 = defaultMaxBytes) {
        self.dir = dir
        self.maxBytes = maxBytes
    }

    /// "2026-11-13T22:40:00.123-03:00 model.load id=qwen3 ok=true ms=812": the time, the record's name, then each field
    /// that has a value, whitespace in a value turned into "_" so a line always splits on spaces.
    public static func line(_ name: String, _ fields: [(String, Any?)], at date: Date = Date()) -> String {
        var l = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon)
            .dateSeparator(.dash).timeSeparator(.colon).dateTimeSeparator(.standard))
        l += " " + name
        for (key, value) in fields {
            guard let value else { continue }
            let text = (value as? CustomStringConvertible)?.description ?? "\(value)"
            l += " \(key)=" + text.split(whereSeparator: \.isWhitespace).joined(separator: "_")
        }
        return l + "\n"
    }

    /// Appends a line in the background.
    public func append(_ line: String) {
        queue.async { self.write(line) }
    }

    /// Appends a line before returning (the app is about to end).
    public func appendNow(_ line: String) {
        queue.sync { write(line) }
    }

    /// Both files' size, in bytes.
    public func sizeBytes() -> Int64 {
        queue.sync { [previous, current].reduce(0) { $0 + (Self.size($1) ?? 0) } }
    }

    /// `header`, then the older file, then the current one (what Save Log writes).
    public func contents(header: String) -> Data {
        queue.sync {
            var data = Data(header.utf8)
            for url in [previous, current] {
                if let d = try? Data(contentsOf: url) { data.append(d) }
            }
            return data
        }
    }

    public func clear() {
        queue.sync {
            for url in [previous, current] { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Waits for the lines already appended (tests).
    public func flush() { queue.sync {} }

    private func write(_ line: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let size = Self.size(current), size > maxBytes {
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: current, to: previous)
        }
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: current) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: current)
        }
    }

    private static func size(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value
    }
}
