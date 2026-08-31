import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const read = (file: string): string => fs.readFileSync(path.resolve(__dirname, file), "utf8");
const walk = (dir: string): string[] => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
});

describe("enum value queries generated trees", () => {
  test("TypeScript emits frozen values, collection and lookup with a literal loop bound", () => {
    const decl = read("../../reference/ts/gen/boring/FloatWidth.ts");
    const ops = read("../../reference/ts/gen/boring/EnumQueriesOps.ts");
    expect(decl).toContain("export const FloatWidth = Object.freeze({");
    expect(decl.match(/Object\.freeze\(\{ kind:/g)?.length).toBe(3);
    expect(decl).toContain("export const FLOAT_WIDTH_ALL = Object.freeze([FloatWidth.F64, FloatWidth.F32, FloatWidth.F16]);");
    expect(decl).toContain("export function floatWidthOfName(name: string): FloatWidth | null");
    expect(ops).toContain("for (let index = 0; index < 3; index += 1)");
    expect(ops).not.toContain("widths.length");
  });

  test("Kotlin uses enum class, entries and a literal bound", () => {
    const decl = read("../../reference/kotlin/gen/boring/FloatWidth.kt");
    const ops = read("../../reference/kotlin/gen/boring/EnumQueriesOps.kt");
    expect(decl).toContain("enum class FloatWidth");
    expect(ops).toContain("FloatWidth.entries");
    expect(ops).toContain("for (index in 0 until 3)");
  });

  test("Swift uses raw value cases, CaseIterable and a literal bound", () => {
    const decl = read("../../reference/swift/gen/boring/FloatWidth.swift");
    const ops = read("../../reference/swift/gen/boring/EnumQueriesOps.swift");
    expect(decl).toContain("enum FloatWidth: String, CaseIterable, Equatable");
    expect(decl).toContain('case f64 = "F64"');
    expect(ops).toContain("FloatWidth.allCases");
    expect(ops).toContain("stride(from: 0, to: 3, by: 1)");
  });

  test("Dart uses enhanced enum labels, lookup and a literal bound", () => {
    const decl = read("../../reference/dart/gen/lib/boring/float_width.dart");
    const ops = read("../../reference/dart/gen/lib/boring/enum_queries_ops.dart");
    expect(decl).toContain("enum FloatWidth {");
    expect(decl).toContain("final String label;");
    expect(decl).toContain("FloatWidth? floatWidthOfName(String name)");
    expect(ops).toContain("index < 3");
  });

  test("Rust emits ALL, name, from_name and a literal range", () => {
    const decl = read("../../reference/rust-gen/src/boring/float_width.rs");
    const ops = read("../../reference/rust-gen/src/boring/enum_queries_ops.rs");
    expect(decl).toContain("pub const ALL: [FloatWidth; 3]");
    expect(decl).toContain("pub fn name(&self) -> &'static str");
    expect(decl).toContain("pub fn from_name(name: &str) -> Option<FloatWidth>");
    expect(ops).toContain("for index in 0..3");
  });

  test("no generated target retains a Type static call", () => {
    const roots = ["../../reference/ts/gen", "../../reference/kotlin/gen", "../../reference/swift/gen", "../../reference/dart/gen", "../../reference/rust-gen/src"]
      .map((root) => path.resolve(__dirname, root));
    for (const file of roots.flatMap(walk)) {
      if (!/\.(ts|kt|swift|dart|rs)$/.test(file)) continue;
      expect(fs.readFileSync(file, "utf8")).not.toMatch(/\bType\.(allEnums|enumConstructor|createEnum)\s*\(/);
    }
  });
});
