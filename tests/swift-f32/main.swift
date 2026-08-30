// Cross-language vector verification for the generated Swift f32 tree
// (feature spec 23): the committed roundtrip binaries must decode to the
// same records every other lane verifies, and re-encoding must reproduce
// the committed bytes exactly (binary spec 05). Every vector value is an
// f32-exact dyadic rational, so the f32 module real and the default lane
// agree byte for byte. This toolchain carries no Foundation module, so
// file reading goes through the POSIX calls of Glibc.

import Glibc

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
    let fd = open(path, O_RDONLY)
    if fd < 0 {
        return []
    }
    defer {
        close(fd)
    }
    var buffer = [UInt8]()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let got = read(fd, &chunk, 4096)
        if got <= 0 {
            break
        }
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
    exit(1)
}
print("all vector checks passed")
