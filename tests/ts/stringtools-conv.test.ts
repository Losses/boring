import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

const walk = (dir: string): string[] => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
});

describe("StringTools conversions lowering", () => {
  test("generated trees contain no unresolved StringTools reference", () => {
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
      for (const file of walk(path.join(root, tree))) {
        // The registry package ships its own StringTools class as its
        // portability layer, so registry files reference that class by
        // name on every target. The unresolved-reference invariant
        // governs the std StringTools lowering of the codec trees.
        if (file.includes(`${path.sep}registry${path.sep}`)) continue;
        expect(fs.readFileSync(file, "utf8")).not.toMatch(/\bStringTools\.[A-Za-z_]\w*\s*\(/u);
      }
    }
  });

  test("each target uses its ruled native conversion spelling", () => {
    const rows = [
      ["reference/ts/gen/boring/StringConvOps.ts", [".toString(16)", ".toUpperCase()", ".padStart(", ".toLowerCase()"]],
      ["reference/kotlin/gen/boring/StringConvOps.kt", [".toString(16)", ".uppercase()", ".padStart(", ".lowercase()"]],
      ["reference/swift/gen/boring/StringConvOps.swift", ["String(10, radix: 16, uppercase: true)", ".uppercased()", "s.count <", ".lowercased()"]],
      ["reference/dart/gen/lib/boring/string_conv_ops.dart", [".toRadixString(16)", ".toUpperCase()", ".padLeft(", ".toLowerCase()"]],
      ["reference/rust-gen/src/boring/string_conv_ops.rs", ["{:X}", "{:0w$X}", ".to_lowercase()", ".to_uppercase()"]],
    ] as const;
    for (const [file, fragments] of rows) {
      const content = fs.readFileSync(path.join(root, file), "utf8");
      for (const fragment of fragments) expect(content).toContain(fragment);
    }
  });

  test("negative hex arguments report the named domain error", async () => {
    const proc = Bun.spawn(["haxe", "examples/ts.hxml", "tests.StringConvProbes"], {
      cwd: root,
      stdout: "pipe",
      stderr: "pipe",
    });
    const stderr = await new Response(proc.stderr).text();
    expect(await proc.exited).not.toBe(0);
    expect(stderr).toContain("StringTools.hex accepts non-negative arguments only");
  });
});
