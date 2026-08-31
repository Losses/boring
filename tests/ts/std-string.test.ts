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

  test("unsupported operands report the named error", async () => {
    const proc = Bun.spawn(["haxe", "examples/ts.hxml", "tests.StdStringProbes"], {
      cwd: root,
      stdout: "pipe",
      stderr: "pipe",
    });
    const stderr = await new Response(proc.stderr).text();
    expect(await proc.exited).not.toBe(0);
    expect(stderr).toContain("Std.string accepts scalars and parameterless enum values only");
  });
});
