import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * The boundary between the two forms an `@:extension` may take in Rust.
 *
 * An inherent impl is legal only on a type this crate declares and only for
 * one method of a given name, so:
 *   - a receiver that lowers to a handle (`Rc<RefCell<T>>`) cannot carry one
 *     at all: the base compiler emitted `impl Rc<RefCell<IntRange>>` and
 *     rustc answered E0116 "cannot define inherent impl for a type outside of
 *     the crate";
 *   - two extension classes claiming one method name for one receiver cannot
 *     both be inherent members: the base compiler emitted two
 *     `impl LayoutResult { fn positioned_clusters }` blocks and rustc answered
 *     E0592 "duplicate definitions with name `positioned_clusters`".
 *
 * Both shapes come from tiqian's engine (IntRange + IntRangeFns; LayoutResult +
 * LayoutResultFns/LayoutResultLineFns), whose generated tree failed to build
 * with exactly those two errors.
 * (ExtensionReceiverOwnership, ExtensionNameCollision)
 */

const root = path.resolve(import.meta.dir, "../../..");
const hxml = "tests/haxe/rust-inherent-impl-boundary/gen/rust.hxml";

function makeScratch(tag: string): string {
  const dir = path.join(root, "out", "inherent-impl-boundary", tag + "-" + randomUUID());
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function generate(out: string): void {
  const run = Bun.spawnSync(["haxe", hxml, "-D", "rust-output=" + out], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  expect(run.exitCode, run.stderr.toString() || run.stdout.toString()).toBe(0);
}

function readGenerated(out: string, module: string): string {
  return fs.readFileSync(path.join(out, "boundaryscope", module + ".rs"), "utf8");
}

test("an extension on a handle receiver lowers as a free function, never impl Rc<RefCell<T>>", () => {
  const out = makeScratch("shape");
  generate(out);

  const rangeFns = readGenerated(out, "int_range_fns");
  expect(rangeFns).toContain(
    "pub fn is_empty_cluster_range(range: Rc<RefCell<IntRange>>) -> bool",
  );
  expect(rangeFns).not.toContain("impl Rc<RefCell<");
}, 180_000);

test("two extensions claiming one method name for one receiver stay distinct and compile", () => {
  const out = makeScratch("build");
  generate(out);

  // Both parts keep the method's own name, in their own module: neither an
  // inherent impl (E0592) nor one module's method shadowing the other.
  expect(readGenerated(out, "layout_result_fns")).toContain(
    "pub fn positioned_clusters(result: LayoutResult) -> u32",
  );
  expect(readGenerated(out, "layout_result_line_fns")).toContain(
    "pub fn positioned_clusters(result: LayoutResult, line: u32) -> u32",
  );
  // No inherent impl survives anywhere in the crate.
  const modules = fs.readdirSync(path.join(out, "boundaryscope")).filter((name) => name.endsWith(".rs"));
  for(const module of modules) {
    expect(
      fs.readFileSync(path.join(out, "boundaryscope", module), "utf8"),
      module + " must not emit an inherent impl on a foreign receiver",
    ).not.toContain("impl Rc<RefCell<");
  }
  // The caller names a contested method by its module path: two imports of one
  // plain name would be E0252.
  const caller = readGenerated(out, "boundary_probe");
  expect(caller).toContain("crate::boundaryscope::layout_result_fns::positioned_clusters(");
  expect(caller).toContain("crate::boundaryscope::layout_result_line_fns::positioned_clusters(");

  // The subject the shapes exist for: the generated crate builds.
  const build = Bun.spawnSync(["cargo", "build"], {
    cwd: out,
    stdout: "pipe",
    stderr: "pipe",
  });
  const output = build.stdout.toString() + build.stderr.toString();
  const errors = output.split("\n").filter((line) => line.startsWith("error"));
  expect(errors, output).toEqual([]);
  expect(build.exitCode, output).toBe(0);
}, 180_000);
