import Darwin
import Foundation

/// A minimal HTTP/1.1 server on 127.0.0.1: GET with an optional "Range: bytes=N-", one request per connection
/// (the Kotlin AssetStoreTest's ServerSocket loop).
final class TestHTTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFd: Int32 = -1
    private var stopped = false
    private var _honorRange = true
    private var _rangeTotalOverride: Int?
    private var _served: [UInt8]
    private var _requests: [String?] = []
    private(set) var port: UInt16 = 0

    init(served: [UInt8]) { _served = served }

    var honorRange: Bool {
        get { lock.withLock { _honorRange } }
        set { lock.withLock { _honorRange = newValue } }
    }
    /// When set, 206 responses claim this total in Content-Range (a file that changed behind a partial download).
    var rangeTotalOverride: Int? {
        get { lock.withLock { _rangeTotalOverride } }
        set { lock.withLock { _rangeTotalOverride = newValue } }
    }
    var requests: [String?] { lock.withLock { _requests } }

    func start() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) }
        }
        port = UInt16(bigEndian: bound.sin_port)
        listen(fd, 16)
        lock.withLock { listenFd = fd }
        // The thread owns the listening socket: it polls so it can notice `stop()`, and closes the descriptor itself, so a
        // later server that reuses the descriptor number never has a stale accept loop stealing its connections.
        Thread.detachNewThread { [self] in
            while !lock.withLock({ stopped }) {
                var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                if poll(&p, 1, 50) <= 0 { continue }
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                handle(c)
            }
            close(fd)
        }
    }

    func stop() { lock.withLock { stopped = true } }

    private func handle(_ c: Int32) {
        defer { close(c) }
        var one: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var request = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !request.suffix(4).elementsEqual([13, 10, 13, 10]) {
            let n = read(c, &buf, buf.count)
            if n <= 0 { return }
            request += buf[0..<n]
            if request.count > 65536 { return }
        }
        let text = String(decoding: request, as: UTF8.self)
        var range: String?
        for line in text.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("range:") {
            range = line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let (honor, served, totalOverride) = lock.withLock { _requests.append(range); return (_honorRange, _served, _rangeTotalOverride) }
        let from = range.flatMap { Int($0.replacingOccurrences(of: "bytes=", with: "").replacingOccurrences(of: "-", with: "")) }
        let head: String
        let body: ArraySlice<UInt8>
        if let from, honor {
            head = "HTTP/1.1 206 Partial Content\r\nContent-Length: \(served.count - from)\r\nContent-Range: bytes \(from)-\(served.count - 1)/\(totalOverride ?? served.count)\r\nConnection: close\r\n\r\n"
            body = served[from...]
        } else {
            head = "HTTP/1.1 200 OK\r\nContent-Length: \(served.count)\r\nConnection: close\r\n\r\n"
            body = served[...]
        }
        send(c, Array(head.utf8))
        send(c, Array(body))
    }

    private func send(_ c: Int32, _ bytes: [UInt8]) {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBytes { write(c, $0.baseAddress, $0.count) }
            if n <= 0 { return }
            off += n
        }
    }
}

/// splitmix64: a reproducible payload (Kotlin used `Random(7).nextBytes`).
func seededBytes(_ count: Int, seed: UInt64) -> [UInt8] {
    var s = seed
    var out = [UInt8]()
    out.reserveCapacity(count)
    while out.count < count {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        for i in 0..<8 where out.count < count { out.append(UInt8(truncatingIfNeeded: z >> (8 * UInt64(i)))) }
    }
    return out
}
