import BoarCore
import BoarRAG
import Foundation
import Testing
import libzstd

/// The zstd frames of pack blocks (boar_sqlite.cpp's zstdDecompress): with and without a content size, concatenated, corrupt.
@Suite struct ZstdDecoderTests {
    private func bytes(_ hex: String) -> Data {
        var d = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            d.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    // `zstd -c` of "hello boar, hello boar, hello boar": from a pipe (no content size) and from a file (with one).
    private let streamed = "28b52ffd04589500006068656c6c6f20626f61722c200100574a12777aa81d"
    private let sized = "28b52ffd24229500006068656c6c6f20626f61722c200100574a12777aa81d"
    private let abc = "28b52ffd0458190000616263990977ad"
    private let text = "hello boar, hello boar, hello boar"

    @Test func decompressesFramesWithAndWithoutContentSize() throws {
        let z = ZstdDecoder()
        #expect(String(decoding: try z.decompress(bytes(streamed)), as: UTF8.self) == text)
        #expect(String(decoding: try z.decompress(bytes(sized)), as: UTF8.self) == text)
    }

    /// SqlTest `zstd decompresses a frame`: "BOAR " × 1000 compressed by libzstd round-trips.
    @Test func decompressesAFrame() throws {
        let text = Data(String(repeating: "BOAR ", count: 1000).utf8)
        var frame = [UInt8](repeating: 0, count: ZSTD_compressBound(text.count))
        let n = text.withUnsafeBytes { src in ZSTD_compress(&frame, frame.count, src.baseAddress, src.count, 3) }
        #expect(ZSTD_isError(n) == 0)
        #expect(try ZstdDecoder().decompress(Data(frame.prefix(n))) == text)
    }

    @Test func decompressesConcatenatedFrames() throws {
        let out = try ZstdDecoder().decompress(bytes(abc) + bytes(streamed))
        #expect(String(decoding: out, as: UTF8.self) == "abc" + text)
    }

    @Test func truncatedOrCorruptInputThrows() {
        let z = ZstdDecoder()
        #expect(throws: ZstdDecoder.Failure.self) { try z.decompress(bytes(streamed).prefix(12)) }
        #expect(throws: ZstdDecoder.Failure.self) { try z.decompress(Data("not zstd at all".utf8)) }
        #expect(throws: ZstdDecoder.Failure.self) { try z.decompress(Data()) }
    }
}
