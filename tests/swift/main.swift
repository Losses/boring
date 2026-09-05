// Cross-language vector verification for the generated Swift tree: the
// committed roundtrip binaries must decode to the same records the other
// targets verify, and re-encoding must reproduce the committed bytes
// exactly (binary spec 05). This toolchain carries no Foundation module,
// so file reading goes through SystemPackage's FileDescriptor, which
// compiles on Linux, macOS, and the Windows MSVC toolchain alike.

import SystemPackage
import Codec

var failures: Int = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("pass: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

func readBytes(_ path: String) -> [UInt8] {
    guard let handle = try? FileDescriptor.open(FilePath(path), .readOnly) else {
        return []
    }
    defer {
        try? handle.close()
    }
    var buffer = [UInt8]()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while let got = try? chunk.withUnsafeMutableBytes({ try handle.read(into: $0) }), got > 0 {
        buffer.append(contentsOf: chunk[0..<got])
    }
    return buffer
}

func expectedRecords() -> [GlyphMetrics] {
    return [
        GlyphMetrics(codePoint: 65, advanceEm: 0.5, bounds: BoundsEm(xMin: 0.03125, yMin: -0.21875, xMax: 0.46875, yMax: 0.03125)),
        GlyphMetrics(codePoint: 19969, advanceEm: 1.0, bounds: BoundsEm(xMin: 0.03125, yMin: -0.875, xMax: 0.96875, yMax: 0.03125)),
        GlyphMetrics(codePoint: 65292, advanceEm: 0.5, bounds: BoundsEm(xMin: 0.03125, yMin: -0.21875, xMax: 0.46875, yMax: 0.03125)),
        GlyphMetrics(codePoint: 65311, advanceEm: 0.75, bounds: BoundsEm(xMin: 0.0625, yMin: -0.15625, xMax: 0.6875, yMax: 0.0625)),
    ]
}

let records = expectedRecords()
let widths: [(FloatWidth, String)] = [
    (FloatWidth.f64, "tests/vectors/roundtrip.bin"),
    (FloatWidth.f32, "tests/vectors/roundtrip-f32.bin"),
    (FloatWidth.f16, "tests/vectors/roundtrip-f16.bin"),
]

for (width, path) in widths {
    let committed = readBytes(path)
    check(committed.count > 0, "\(path) loads")

    var decoded: [GlyphMetrics]? = nil
    var decodeFailure: String? = nil
    do {
        decoded = try VectorCodec.decode(committed)
    } catch {
        decodeFailure = "\(error)"
    }
    check(decodeFailure == nil && decoded == records, "\(path) decodes to the shared records")

    if decoded != nil {
        let reencoded = VectorCodec.encode(records, width)
        check(reencoded == committed, "re-encoding \(path) reproduces the committed bytes")
    }
}

// A magic outside the table refuses the block; the reader never guesses a
// layout (binary spec 05).
var badMagic = readBytes("tests/vectors/roundtrip.bin")
badMagic[3] = UInt8(ascii: "4")
var badMagicRejected = false
do {
    _ = try VectorCodec.decode(badMagic)
} catch {
    badMagicRejected = true
}
check(badMagicRejected, "an unknown magic rejects the block")

if failures > 0 {
    print("\(failures) check(s) failed")
    fatalError("\(failures) vector check(s) failed")
}
print("all vector checks passed")
