import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const read = (file: string) => {
  expect(fs.existsSync(file)).toBe(true);
  return fs.readFileSync(file, "utf8");
};

describe("array element iteration generated tree", () => {
  test("TypeScript uses a single-read indexed bound for all array subjects", () => {
    const content = read(path.resolve(__dirname, "../../reference/ts/gen/boring/ArrayIterationOps.ts"));
    expect(content).toContain("for (let _g_index = 0, count = values.length; _g_index < count; _g_index += 1)");
    expect(content).toContain("for (let _g_index = 0, count2 = values.length; _g_index < count2; _g_index += 1)");
    expect(content).toContain("const _g1 = holder.values;");
    expect(content).toContain("for (let _g_index = 0, count3 = _g1.length; _g_index < count3; _g_index += 1)");
  });

  test("Kotlin emits element for loops", () => {
    const content = read(path.resolve(__dirname, "../../reference/kotlin/gen/boring/ArrayIterationOps.kt"));
    expect(content).toContain("for (item in values) {\n            total += item");
    expect(content).toContain("val _g1 = holder.values\n        for (item in _g1) {");
  });

  test("Rust emits element for loops", () => {
    const content = read(path.resolve(__dirname, "../../reference/rust-gen/src/boring/array_iteration_ops.rs"));
    expect(content).toContain("for &mut item in values {\n            total += item");
    expect(content).toContain("for &item in values {\n            total += item");
    expect(content).toContain("let _g1 = holder.values;\n        for &item in &_g1 {");
  });

  test("Swift emits element for loops", () => {
    const content = read(path.resolve(__dirname, "../../reference/swift/gen/boring/ArrayIterationOps.swift"));
    expect(content).toContain("for item in values {\n            total += item");
    expect(content).toContain("let _g1 = holder.values\n        for item in _g1 {");
  });

  test("Dart emits element for loops", () => {
    const content = read(path.resolve(__dirname, "../../reference/dart/gen/lib/boring/array_iteration_ops.dart"));
    expect(content).toContain("for (var item in values) {\n    total += item");
    expect(content).toContain("final _g1 = holder.values;\n  for (var item in _g1) {");
  });
});
