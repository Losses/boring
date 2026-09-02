import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

describe("Std.string lowering", () => {
  test("generated trees contain no unresolved Std reference", () => {
    const trees = [
      "reference/ts/gen",
      "reference/kotlin/gen",
      "reference/kotlin-f32/gen",
      "reference/rust-gen/src",
      "reference/rust-f32-gen/src",
      "reference/swift/gen",
      "reference/swift-f32/gen",
      "reference/dart/gen",
    ];
    for (const tree of trees) {
      const files = fs.readdirSync(path.join(root, tree), { recursive: true, withFileTypes: true });
      for (const entry of files) {
        if (!entry.isFile()) continue;
        const file = path.join(entry.parentPath, entry.name);
        expect(fs.readFileSync(file, "utf8")).not.toMatch(/\bStd\.[A-Za-z_]\w*\s*\(/u);
      }
    }
  });

  test("Kotlin concatenation keeps Std.string scalar operands bare", () => {
    const content = fs.readFileSync(path.join(root, "reference/kotlin/gen/boring/StdStringOps.kt"), "utf8");
    expect(content).toContain('return "string=" + value');
    expect(content).toContain('return "int=" + value');
    expect(content).toContain('return "float=" + value');
    expect(content).toContain('return "bool=" + value');
    expect(content).not.toContain('"string=" + (value).toString()');
  });

  test("enum operands use each target constructor-name read", () => {
    const ts = fs.readFileSync(path.join(root, "reference/ts/gen/boring/StdStringOps.ts"), "utf8");
    const kotlin = fs.readFileSync(path.join(root, "reference/kotlin/gen/boring/StdStringOps.kt"), "utf8");
    const rust = fs.readFileSync(path.join(root, "reference/rust-gen/src/boring/std_string_ops.rs"), "utf8");
    const swift = fs.readFileSync(path.join(root, "reference/swift/gen/boring/StdStringOps.swift"), "utf8");
    const dart = fs.readFileSync(path.join(root, "reference/dart/gen/lib/boring/std_string_ops.dart"), "utf8");

    expect(ts).toContain("value.kind");
    expect(kotlin).toContain("value.name");
    expect(swift).toContain("value.rawValue");
    expect(dart).toContain("value.label");
    expect(rust).toContain("value.name()");
  });

  test("Rust standalone scalars use to_string", () => {
    const content = fs.readFileSync(path.join(root, "reference/rust-gen/src/boring/std_string_ops.rs"), "utf8");
    expect(content).toContain("pub fn int_value(value: u32) -> String {\n        return (value).to_string();");
  });

  test("array operands use one single-pass builder in every target", () => {
    const rows = [
      ["reference/ts/gen/boring/StdStringOps.ts", 'let out = "["', "const n =", "for (let i = 0; i < n; i += 1)"],
      ["reference/kotlin/gen/boring/StdStringOps.kt", "StringBuilder()", "val n =", "while (i < n)"],
      ["reference/rust-gen/src/boring/std_string_ops.rs", "String::new()", "let n =", 'write!(out, "{}"'],
      ["reference/swift/gen/boring/StdStringOps.swift", 'var out = "["', "let n =", "while i < n"],
      ["reference/dart/gen/lib/boring/std_string_ops.dart", 'StringBuffer("[")', "final n =", "while (i < n)"],
    ] as const;
    for (const [file, accumulator, length, loop] of rows) {
      const content = fs.readFileSync(path.join(root, file), "utf8");
      expect(content).toContain(accumulator);
      expect(content).toContain(length);
      expect(content).toContain(loop);
      expect(content).not.toMatch(/\.map\(|join|joinToString|joined/u);
    }
  });

  test("unsupported operands report the named error", async () => {
    const proc = Bun.spawn(["haxe", "examples/ts.hxml", "tests.StdStringProbes"], {
      cwd: root,
      stdout: "pipe",
      stderr: "pipe",
    });
    const stderr = await new Response(proc.stderr).text();
    expect(await proc.exited).not.toBe(0);
    expect(stderr).toContain("Std.string accepts scalars, enum values, records, and arrays of them only");
  });
});
