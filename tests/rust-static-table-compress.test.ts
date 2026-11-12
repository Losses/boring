import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * Rust static-table compression requirement (Emit-StaticTableCompress).
 *
 * A large `static final Array<String>` lowers to one joined `&str` plus a
 * split+map; the element-wise form would be thousands of `UString::from`
 * calls. The compressed value must equal the element-wise value, and an
 * element containing the separator must fall back to the element-wise form.
 */

const root = path.resolve(import.meta.dir, "..");
const scratch =
  Bun.env.BORING_STATIC_TABLE_OUT ??
  path.join(root, "out", "static-table-compress", "test-" + randomUUID());

function observe(command: string[]) {
  const result = Bun.spawnSync(command, {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

function read(p: string): string {
  return fs.readFileSync(p, "utf8");
}

function staticFile(out: string, name: string): string {
  return path.join(out, "tests", "probe", name + "_support", "probe", name.replace(/_test$/, "") + ".rs");
}

function compressedValues(source: string): string[] {
  const m = source.match(/const __DATA: &str = "([^"]*)"/);
  if (!m) throw new Error("compressed static data not found");
  return m[1].split("|");
}

function elementWiseValues(source: string): string[] {
  const values: string[] = [];
  const re = /UString::from\("([^"]*)"\)\.to_ustring\(\)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source)) != null) values.push(m[1]);
  return values;
}

test("static table compression equals element-wise output and falls back on the separator", () => {
  fs.mkdirSync(scratch, { recursive: true });

  const compressedOut = path.join(scratch, "compressed");
  const elementWiseOut = path.join(scratch, "elementwise");
  const fallbackOut = path.join(scratch, "fallback");

  const compressed = observe([
    "haxe",
    "tests/haxe/rust-static-table-compress/gen/rust.hxml",
    "-D",
    "rust-output=" + compressedOut,
  ]);
  expect(compressed.code, "compressed generation failed: " + compressed.stderr).toBe(0);

  const elementWise = observe([
    "haxe",
    "tests/haxe/rust-static-table-compress/gen/rust.hxml",
    "-D",
    "rust_static_table_compress=none",
    "-D",
    "rust-output=" + elementWiseOut,
  ]);
  expect(elementWise.code, "element-wise generation failed: " + elementWise.stderr).toBe(0);

  const fallback = observe([
    "haxe",
    "tests/haxe/rust-static-table-compress/gen/rust-fallback.hxml",
    "-D",
    "rust-output=" + fallbackOut,
  ]);
  expect(fallback.code, "fallback generation failed: " + fallback.stderr).toBe(0);

  const compressedSrc = read(staticFile(compressedOut, "static_table_test"));
  const elementWiseSrc = read(staticFile(elementWiseOut, "static_table_test"));
  const fallbackSrc = read(
    path.join(fallbackOut, "tests", "probe", "static_table_fallback_test_support", "probe", "static_table_fallback.rs"),
  );

  expect(compressedSrc).toContain("const __DATA: &str =");
  expect(elementWiseSrc).not.toContain("const __DATA: &str =");
  expect(compressedValues(compressedSrc)).toEqual(elementWiseValues(elementWiseSrc));
  expect(compressedValues(compressedSrc).length).toBe(300);

  // An element containing the separator must fall back to element-wise.
  expect(fallbackSrc).not.toContain("const __DATA: &str =");
  expect(elementWiseValues(fallbackSrc)).toHaveLength(300);
}, 180000);
