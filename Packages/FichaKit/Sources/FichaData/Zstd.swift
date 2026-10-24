import Foundation
internal import libzstd

// zstd, which current Anki compresses its packages' members with, through
// the zstd library itself (ADR 0015): Apple's Compression framework has no
// zstd.

/// What `compressed`, one zstd frame or several one after another, holds
/// once decompressed. It decompresses as a stream, a buffer at a time, as
/// zstd's own example does (`examples/streaming_decompression.c`), since
/// Anki's frames don't say how large they are. Input that ends in the middle
/// of a frame, or that holds no frame, is an error.
func zstdDecompressed(_ compressed: Data) throws(ZstdProblem) -> Data {
    guard let context = ZSTD_createDCtx() else {
        throw ZstdProblem("zstd couldn't start decompressing")
    }
    defer { ZSTD_freeDCtx(context) }
    var decompressed = Data()
    var buffer = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())
    // What zstd last said its frame still needs, 0 once the frame is whole:
    // with no frame yet, it needs one.
    var needed = 1
    let failure: String? = compressed.withUnsafeBytes { source in
        var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
        // zstd takes a frame's last byte only once it has handed out all
        // that the frame holds, so all input taken means all output given.
        while input.pos < input.size {
            let result = buffer.withUnsafeMutableBytes { out in
                var output = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                let result = ZSTD_decompressStream(context, &output, &input)
                decompressed.append(contentsOf: out[..<output.pos])
                return result
            }
            guard ZSTD_isError(result) == 0 else {
                return String(cString: ZSTD_getErrorName(result))
            }
            needed = result
        }
        return nil
    }
    if let failure {
        throw ZstdProblem("zstd couldn't decompress: \(failure)")
    }
    guard needed == 0 else {
        throw ZstdProblem("zstd's input ends in the middle of a frame")
    }
    return decompressed
}

/// Why bytes can't be decompressed with zstd: they're damaged, cut short, or
/// not zstd.
struct ZstdProblem: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
