import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("number classification generated tree", () => {
  const tsFile = path.resolve(__dirname, "../../reference/ts/gen/boring/NumberClassifyOps.ts");
  const kotlinFile = path.resolve(__dirname, "../../reference/kotlin/gen/boring/NumberClassifyOps.kt");
  const rustFile = path.resolve(__dirname, "../../reference/rust-gen/src/boring/number_classify_ops.rs");
  const swiftFile = path.resolve(__dirname, "../../reference/swift/gen/boring/NumberClassifyOps.swift");
  const dartFile = path.resolve(__dirname, "../../reference/dart/gen/lib/boring/number_classify_ops.dart");

  test("Math.isFinite and Math.isNaN render as native predicates on every target", () => {
    const ts = fs.readFileSync(tsFile, "utf8");
    expect(ts).toContain("return Number.isFinite(value);");
    expect(ts).toContain("return Number.isNaN(value);");

    const kotlin = fs.readFileSync(kotlinFile, "utf8");
    expect(kotlin).toContain("return (value).isFinite()");
    expect(kotlin).toContain("return (value).isNaN()");

    const rust = fs.readFileSync(rustFile, "utf8");
    expect(rust).toContain("return (value).is_finite();");
    expect(rust).toContain("return (value).is_nan();");

    const swift = fs.readFileSync(swiftFile, "utf8");
    expect(swift).toContain("return (value).isFinite");
    expect(swift).toContain("return (value).isNaN");

    const dart = fs.readFileSync(dartFile, "utf8");
    expect(dart).toContain("return (value).isFinite;");
    expect(dart).toContain("return (value).isNaN;");
  });
});
