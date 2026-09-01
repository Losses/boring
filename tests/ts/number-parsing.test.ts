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
    expect(kotlin).toContain("NumberParsing.parseFloat("); expect(kotlin).toContain("NumberParsing.parseInt("); expect(kotlin).not.toContain("Regex(");
    const swift = read("reference/swift/gen/boring/NumberParsingOps.swift");
    expect(swift).toContain("NumberParsing.parseFloat("); expect(swift).toContain("NumberParsing.parseInt("); expect(swift).not.toContain("Double(value)"); expect(swift).not.toContain("Int32(value)");
    const dart = read("reference/dart/gen/lib/boring/number_parsing_ops.dart");
    expect(dart).toContain("NumberParsing.parseFloat("); expect(dart).toContain("NumberParsing.parseInt("); expect(dart).not.toContain("RegExp(");
    const rust = read("reference/rust-gen/src/boring/number_parsing_ops.rs");
    expect(rust).toContain("parse::<f64>"); expect(rust).toContain("-> Option<i32>");
    expect(read("reference/rust-f32-gen/src/boring/number_parsing_ops.rs")).toContain("parse::<f32>");
    expect(read("reference/kotlin-f32/gen/boring/NumberParsingOps.kt")).toContain("NumberParsing.parseFloat(");
    expect(read("reference/swift-f32/gen/boring/NumberParsingOps.swift")).toContain("NumberParsing.parseFloat(");
  });
});
