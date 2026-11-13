import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");
const read = (file: string): string => fs.readFileSync(path.join(root, file), "utf8");
describe("number parsing renderings", () => {
  test("all target trees use the validated implementation", () => {
    const ts = read("reference/ts/gen-tests/boring/NumberParsingOps.test.ts");
    expect(ts).toContain("Number.parseFloat");
    expect(ts).toContain("Number.parseInt");
    expect(ts).toContain("charCodeAt");
    expect(ts).toContain("Number.NaN");
    expect(ts).toContain("-2147483648");
    expect(ts).not.toContain("RegExp");
    expect(ts).not.toContain(".replace(");
    expect(ts).not.toContain(".test(");
    const kotlin = read("reference/kotlin/gen/boring/NumberParsingOps.kt");
    expect(fs.existsSync(path.join(root, "reference/kotlin/gen/runtime/NumberParsing.kt"))).toBe(false);
    expect(kotlin).toContain("toDoubleOrNull"); expect(kotlin).toContain("toIntOrNull"); expect(kotlin).toContain("2147483647");
    withTargetTree("swift", "number-parsing: all target trees use the validated implementation (swift)", () => {
      const swift = read("reference/swift/gen/boring/NumberParsingOps.swift");
      const swiftRuntime = read("reference/swift/gen/Runtime.swift");
      expect(swiftRuntime).not.toContain("NumberParsing");
      expect(swiftRuntime).toContain("guard let n = Int64(digits, radix: hex ? 16 : 10) else { return nil }");
      expect(swiftRuntime).toContain("return value >= -2147483648 && value <= 2147483647 ? Int32(value) : nil");
      // The ops module hands the runtime a native String, so it converts the
      // [UInt16] argument first (INTERFACE-REQUIREMENTS.md:235); the inlined
      // scan itself lives in parseIntRuntime (stdlib/14:121 describes the
      // scan; its declaration site is elsewhere).
      expect(swift).toContain('return parseIntRuntime(String(decoding: value, as: UTF16.self))');
      expect(swiftRuntime).not.toContain("NSRegularExpression"); expect(swiftRuntime).not.toContain("import Foundation");
    });
    const dart = read("reference/dart/gen/lib/boring/number_parsing_ops.dart");
    expect(read("reference/dart/gen/lib/runtime.dart")).not.toContain("NumberParsing");
    expect(dart).toContain("tryParse"); expect(dart).toContain("2147483647");
    const rust = read("reference/rust/gen/boring/number_parsing_ops.rs");
    expect(rust).toContain("u_string::parse_f64(&(value))"); expect(rust).toContain("u_string::parse_i32(&(value))");
    expect(rust).toContain("-> Option<i32>"); expect(rust).not.toContain("parse::<");
    // The parse edge keeps the binary64 protocol width in both feature
    // settings (RustRuntime.hx parse_f64 comment) and the closing cast names
    // the TiqianFloat alias, so the f32 tree reads the same entry.
    expect(read("reference/rust-f32/gen/boring/number_parsing_ops.rs")).toContain("u_string::parse_f64(&(value)) as crate::TiqianFloat");
    expect(read("reference/kotlin-f32/gen/boring/NumberParsingOps.kt")).toContain("toFloatOrNull");
    withTargetTree("swift-f32", "number-parsing: all target trees use the validated implementation (swift-f32)", () => {
      const swiftF32 = read("reference/swift-f32/gen/boring/NumberParsingOps.swift");
      const swiftF32Runtime = read("reference/swift-f32/gen/Runtime.swift");
      expect(swiftF32Runtime).toContain("guard let n = Int64(digits, radix: hex ? 16 : 10) else { return nil }");
      expect(swiftF32Runtime).toContain("return value >= -2147483648 && value <= 2147483647 ? Int32(value) : nil");
      // Same host-edge conversion as the f64 tree: the module converts the
      // [UInt16] argument to a native String before the scan.
      expect(swiftF32).toContain("return parseIntRuntime(String(decoding: value, as: UTF16.self))");
      expect(swiftF32Runtime).not.toContain("import Foundation"); expect(swiftF32Runtime).not.toContain("NSRegularExpression");
    });
  });
});
