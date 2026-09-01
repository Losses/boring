import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
const root = path.resolve(__dirname, "../..");
const read = (file: string): string => fs.readFileSync(path.join(root, file), "utf8");
describe("number parsing renderings", () => {
  test("all target trees use the validated implementation", () => {
    expect(read("reference/ts/gen/boring/NumberParsingOps.ts")).toContain("Number.parseFloat");
    expect(read("reference/ts/gen/boring/NumberParsingOps.ts")).toContain("Number.parseInt");
    const kotlin = read("reference/kotlin/gen/boring/NumberParsingOps.kt");
    expect(fs.existsSync(path.join(root, "reference/kotlin/gen/runtime/NumberParsing.kt"))).toBe(false);
    expect(kotlin).toContain("toDoubleOrNull"); expect(kotlin).toContain("toIntOrNull"); expect(kotlin).toContain("2147483647");
    const swift = read("reference/swift/gen/boring/NumberParsingOps.swift");
    const swiftRuntime = read("reference/swift/gen/Runtime.swift");
    expect(swiftRuntime).not.toContain("NumberParsing");
    expect(swift).toContain("Int64(t)"); expect(swift).toContain("2147483647"); expect(swiftRuntime).not.toContain("NSRegularExpression"); expect(swiftRuntime).not.toContain("import Foundation");
    const dart = read("reference/dart/gen/lib/boring/number_parsing_ops.dart");
    expect(read("reference/dart/gen/runtime.dart")).not.toContain("NumberParsing");
    expect(dart).toContain("tryParse"); expect(dart).toContain("2147483647");
    const rust = read("reference/rust-gen/src/boring/number_parsing_ops.rs");
    expect(rust).toContain("parse::<f64>"); expect(rust).toContain("-> Option<i32>");
    expect(read("reference/rust-f32-gen/src/boring/number_parsing_ops.rs")).toContain("parse::<f32>");
    expect(read("reference/kotlin-f32/gen/boring/NumberParsingOps.kt")).toContain("toFloatOrNull");
    const swiftF32 = read("reference/swift-f32/gen/boring/NumberParsingOps.swift");
    const swiftF32Runtime = read("reference/swift-f32/gen/Runtime.swift");
    expect(swiftF32).toContain("Int64(t)"); expect(swiftF32Runtime).not.toContain("import Foundation"); expect(swiftF32Runtime).not.toContain("NSRegularExpression");
  });
});
