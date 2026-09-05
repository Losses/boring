import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

const walk = (dir: string): string[] => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
  const full = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(full) : [full];
});

describe("StringTools conversions lowering", () => {
  // The runtime StringTools resident (routed statics per feature spec 49)
  // legally references its own statics, and the ts/swift/dart/rust targets
  // legally spell consumer calls as `StringTools.<name>(` behind an import.
  // The scans below keep the original teeth: Kotlin consumers must qualify
  // through the resident module, and every tree that references the
  // resident must also emit it.
  test("kotlin trees qualify StringTools statics through the runtime resident", () => {
    for (const tree of ["reference/kotlin/gen", "reference/kotlin-f32/gen"]) {
      for (const file of walk(path.join(root, tree))) {
        if (file.includes(`runtime${path.sep}`)) continue;
        const bare = fs.readFileSync(file, "utf8").match(/(?<!runtime\.)\bStringTools\.[A-Za-z_]\w*\s*\(/gu);
        expect(bare, `${path.relative(root, file)}: bare StringTools reference outside the runtime resident`).toBeNull();
      }
    }
  });

  test("every tree referencing StringTools statics emits its runtime resident", () => {
    const residents: Record<string, string> = {
      "reference/ts/gen": "runtime.ts",
      "reference/kotlin/gen": path.join("runtime", "StringTools.kt"),
      "reference/kotlin-f32/gen": path.join("runtime", "StringTools.kt"),
      "reference/rust-gen/src": path.join("runtime", "string_tools.rs"),
      "reference/rust-f32-gen/src": path.join("runtime", "string_tools.rs"),
      "reference/swift/gen": "Runtime.swift",
      "reference/swift-f32/gen": "Runtime.swift",
      "reference/dart/gen": "runtime.dart",
    };
    for (const [tree, resident] of Object.entries(residents)) {
      const residentPath = path.join(root, tree, resident);
      let referenced = false;
      for (const file of walk(path.join(root, tree))) {
        if (file === residentPath) continue;
        if (/\bStringTools(?:::|\.)[A-Za-z_]\w*\s*\(/u.test(fs.readFileSync(file, "utf8"))) {
          referenced = true;
          break;
        }
      }
      if (referenced) {
        expect(fs.existsSync(residentPath), `${path.relative(root, residentPath)} missing`).toBe(true);
        expect(fs.readFileSync(residentPath, "utf8")).toContain("lpad");
      }
    }
  });

  test("each target uses its ruled native conversion spelling", () => {
    const rows = [
      ["reference/ts/gen/boring/StringConvOps.ts", [".toString(16)", ".toUpperCase()", ".padStart(", ".toLowerCase()"]],
      ["reference/kotlin/gen/boring/StringConvOps.kt", [".toString(16)", ".uppercase()", ".padStart(", ".lowercase()"]],
      ["reference/swift/gen/boring/StringConvOps.swift", ["String(UInt32(bitPattern: 10), radix: 16, uppercase: true)", ".uppercased()", "s.count <", ".lowercased()"]],
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
