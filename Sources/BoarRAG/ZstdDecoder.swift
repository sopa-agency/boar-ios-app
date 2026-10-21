import BoarCore
import Foundation
import libzstd

/// zstd frame decompression for format-2 pack blocks (the Kotlin side's `zstdDecompress` in boar_sqlite.cpp): one frame, or
/// several concatenated, streamed so frames without a content size work too. A truncated or corrupt frame throws.
public struct ZstdDecoder: Zstd {
    public struct Failure: Error, CustomStringConvertible, Equatable {
        public var description: String
    }

    public init() {}

    public func decompress(_ src: Data) throws -> Data {
        guard let dctx = ZSTD_createDCtx() else { throw Failure(description: "zstd: out of memory") }
        defer { ZSTD_freeDCtx(dctx) }
        var out = Data()
        if let hint = src.withUnsafeBytes({ raw -> UInt64? in
            let h = ZSTD_getFrameContentSize(raw.baseAddress, raw.count)
            return h == ZSTD_CONTENTSIZE_UNKNOWN || h == ZSTD_CONTENTSIZE_ERROR || h >= (1 << 31) ? nil : UInt64(h)
        }) {
            out.reserveCapacity(Int(hint))
        }
        var buf = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())
        var failure: String?
        var last = 0
        src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var input = ZSTD_inBuffer(src: raw.baseAddress, size: raw.count, pos: 0)
            buf.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                // Feed all input; keep draining while a call fills the whole output buffer.
                while true {
                    var o = ZSTD_outBuffer(dst: dst.baseAddress, size: dst.count, pos: 0)
                    last = ZSTD_decompressStream(dctx, &o, &input)
                    if ZSTD_isError(last) != 0 {
                        failure = String(cString: ZSTD_getErrorName(last))
                        return
                    }
                    out.append(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), count: o.pos)
                    if input.pos == input.size && o.pos < o.size { return }
                }
            }
        }
        if let failure { throw Failure(description: "zstd: \(failure)") }
        if last != 0 { throw Failure(description: "zstd: truncated frame") }
        return out
    }
}
