import { expect, test } from "bun:test";

// The generation half of block A. The macOS run.sh proves the emitted text
// compiles and runs; this test pins the shapes on every platform and drives
// the A6 negative case (an out parameter must be an addressable local).

const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_SWIFT_POINTER_OUT ?? `${root}/out/swift-pointer-check/test-${crypto.randomUUID()}`;

function run(command: string[]): { stdout: string; stderr: string; code: number | null } {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  return { stdout: result.stdout.toString(), stderr: result.stderr.toString(), code: result.exitCode };
}

test("A1/A2 emit C pointer, out-parameter and buffer shapes", async () => {
  const existing = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existing.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  Bun.spawnSync(["mkdir", "-p", out]);

  const generate = run([
    "haxe", "tests/swift-pointer-check/check.hxml",
    "-D", `swift-output=${out}/gen`,
    "-D", `swift-test-output=${out}/tests`,
  ]);
  expect(generate.code, generate.stderr || generate.stdout).toBe(0);

  const source = await Bun.file(`${out}/gen/ptr/OutFixture.swift`).text();
  // T* out parameter: the wrapper field is the addressable storage.
  expect(source).toContain("let ascent = Out<CGFloat>(0.0)");
  expect(source).toContain("CTLineGetTypographicBounds(line, &ascent.value, &descent.value, &leading.value)");
  expect(source).toContain("CTLineGetTypographicBounds(line, nil, nil, nil)");
  // T** out parameter: the same wrapper, with an optional raw pointer field.
  expect(source).toContain("let values = Out<UnsafeRawPointer?>(nil)");
  expect(source).toContain("CFArrayGetValues(runs, CFRangeMake(Int(0), Int(1)), &values.value)");
  expect(source).toContain("Unmanaged<CTRun>.fromOpaque(values.value!).takeUnretainedValue()");
  // Temporary C buffers: pointer allocation, direct pointer argument, subscript read.
  expect(source).toContain("UnsafeMutablePointer<CGGlyph>.allocate(capacity: Int(glyphCount))");
  expect(source).toContain("UnsafeMutablePointer<CGPoint>.allocate(capacity: Int(glyphCount))");
  expect(source).toContain("CTRunGetGlyphs(run, CFRangeMake(Int(0), Int(0)), glyphs)");
  expect(source).toContain("glyphs[Int(0)]");
  expect(source).toContain("glyphs.deinitialize(count: Int(glyphCount)); glyphs.deallocate()");
  // A3: a C string out buffer, compared as UTF-8 bytes.
  expect(source).toContain("CFStringGetCString(String(decoding: Array(\"Helvetica\".utf16), as: UTF16.self) as CFString, cbuf");
  expect(source).toContain("Int32(cbuf[Int(0)])");
  // A4: a CGRect array written by the C API, then read through fields.
  expect(source).toContain("UnsafeMutablePointer<CGRect>.allocate(capacity: Int(n))");
  expect(source).toContain("CTFontGetBoundingRectsForGlyphs(font, CTFontOrientation.horizontal, hglyphs, rects, Int(n))");
  expect(source).toContain("let w = rect.size.width");
  // A5: a labeled Swift initializer plus the drawing call.
  expect(source).toContain("CGContext(data: pixels, width: Int(width), height: Int(height), bitsPerComponent: Int(8), bytesPerRow: Int(width &* 4), space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))");
  expect(source).toContain("CTFontDrawGlyphs(font, hglyphs, drawPositions, Int(n), ctx)");
  expect(source).toContain("pixels[Int(i2)]");
});

test("A6 rejects an out parameter that is not an addressable local", () => {
  const result = run([
    "haxe", "tests/swift-pointer-check/check-negative.hxml",
    "-D", `swift-output=${out}/negative`,
    "-D", `swift-test-output=${out}/negative-tests`,
  ]);
  const text = result.stderr + result.stdout;
  expect(result.code, "the negative fixture must fail generation").not.toBe(0);
  expect(text).toContain("an out parameter needs a plain local or field");
});
