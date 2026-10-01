import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { availableTargets, installTargetTreeReport, targetTreeDir, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");

describe("Std.string lowering", () => {
  test("generated trees contain no unresolved Std reference", () => {
    const trees = availableTargets(
      ["ts", "kotlin", "kotlin-f32", "rust", "rust-f32", "swift", "swift-f32", "dart"],
      "std-string: generated trees contain no unresolved Std reference",
    );
    for (const tree of trees) {
      const files = fs.readdirSync(targetTreeDir(tree), { recursive: true, withFileTypes: true });
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
    expect(content).toContain('return "float=" + boring.runtime.FPHelper.formatFloat(value)');
    expect(content).toContain('return "bool=" + value');
    expect(content).not.toContain('"string=" + (value).toString()');
  });

  test("enum operands use each target constructor-name read", () => {
    const ts = fs.readFileSync(path.join(root, "reference/ts/gen/boring/StdStringOps.ts"), "utf8");
    const kotlin = fs.readFileSync(path.join(root, "reference/kotlin/gen/boring/StdStringOps.kt"), "utf8");
    const rust = fs.readFileSync(path.join(root, "reference/rust/gen/boring/std_string_ops.rs"), "utf8");
    const dart = fs.readFileSync(path.join(root, "reference/dart/gen/lib/boring/std_string_ops.dart"), "utf8");

    expect(ts).toContain("value.kind");
    expect(kotlin).toContain("value.name");
    withTargetTree("swift", "std-string: enum operands use each target constructor-name read", () => {
      const swift = fs.readFileSync(path.join(root, "reference/swift/gen/boring/StdStringOps.swift"), "utf8");
      expect(swift).toContain("value.rawValue");
    });
    expect(dart).toContain("value.label");
    expect(rust).toContain("value.name()");
  });

  test("Rust standalone scalars route unsigned Int through int_text", () => {
    const content = fs.readFileSync(path.join(root, "reference/rust/gen/boring/std_string_ops.rs"), "utf8");
    // The parameter is `u32` -- the unsigned domain -- so it goes through
    // IntText::int_text rather than Display. Commit ef3c874b (int_text domain)
    // routed only the SIGNED-domain values (indexOf, unary neg, i32 locals,
    // fpHelper i32, closure params) through direct to_string and says so in its
    // message. This expectation still named the pre-ef3c874b form and was missed
    // when 40cf0ad0 refreshed "stale Rust string expectations across 13 files".
    //
    // It stayed invisible because reference/rust/gen is git-ignored build output
    // that nothing regenerated: the stale tree still emitted the old form, so
    // the stale expectation kept passing against stale artifacts. Regenerating
    // the tree exposed it. The generated output is correct; this expectation was
    // what had gone out of date.
    expect(content).toContain(
      'pub fn std_string_ops_int_value(value: u32) -> UString {\n        return UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(value)).as_str());',
    );
  });

  test("array operands use one single-pass builder in every target", () => {
    const rows = [
      ["ts", "reference/ts/gen/boring/StdStringOps.ts", 'let out = "["', "const n =", "for (let i = 0; i < n; i += 1)"],
      ["kotlin", "reference/kotlin/gen/boring/StdStringOps.kt", "StringBuilder()", "val n =", "while (i < n)"],
      ["rust", "reference/rust/gen/boring/std_string_ops.rs", "String::new()", "let n =", 'write!(out, "{}"'],
      ["swift", "reference/swift/gen/boring/StdStringOps.swift", 'var out = "["', "let n =", "while i < n"],
      ["dart", "reference/dart/gen/lib/boring/std_string_ops.dart", 'StringBuffer("[")', "final n =", "while (i < n)"],
    ] as const;
    for (const [target, file, accumulator, length, loop] of rows) {
      withTargetTree(target, "std-string: array operands use one single-pass builder in every target", () => {
        const content = fs.readFileSync(path.join(root, file), "utf8");
        expect(content).toContain(accumulator);
        expect(content).toContain(length);
        expect(content).toContain(loop);
        expect(content).not.toMatch(/\.map\(|join|joinToString|joined/u);
      });
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
    // Full haxe pipeline under load; the explicit timeout raises only the
    // harness patience for that subprocess, never the asserted behavior.
  }, 120000);

  test("nullable operands are rejected on every target", async () => {
    for (const target of ["ts", "kotlin", "swift", "dart", "rust"]) {
      const proc = Bun.spawn(["haxe", `examples/${target}.hxml`, "tests.StdNullStringProbes"], {
        cwd: root,
        stdout: "pipe",
        stderr: "pipe",
      });
      const stderr = await new Response(proc.stderr).text();
      expect(await proc.exited).not.toBe(0);
      expect(stderr).toContain("Std.string does not accept Null<T> operands; compare against null first");
    }
    // Five haxe macro-compiler runs (one per target lane) measured at
    // 141.8 s total (baseline machine, quiet window); 300_000 keeps ≥2×
    // margin. The explicit timeout raises only the harness patience for
    // those subprocesses, never the asserted behavior.
  }, 300_000);
});
