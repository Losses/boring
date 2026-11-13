import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * Two message-only exceptions declared in one Haxe module.
 *
 * The emitter keeps its message-only exception registry keyed by module, so a
 * module with two of them holds only the last registered class. Two catch-side
 * readers used to read the class name back out of that registry:
 *   - Compiler.regionErrorNameOf decides the error type of a fallible block
 *     parameter from the try region around its call, so the block was typed
 *     `Result<(), MsgOnlySecond>` while its body produced `MsgOnlyFirst`;
 *   - RustExpr.caughtPayloadEnum types the try region's own `Result`, so the
 *     statement region was annotated `Result<(), MsgOnlySecond>` around an
 *     `Err(MsgOnlyFirst::new(..))`, which rustc rejected with E0308.
 *
 * Both readers ask the caught class instead, which is what the thrown-payload
 * scan already does.
 */

const root = path.resolve(import.meta.dir, "../../..");
const hxml = "tests/haxe/messageonly-two-in-module/gen/rust.hxml";

function makeScratch(tag: string): string {
  const dir = path.join(root, "out", "messageonly-two-in-module", tag + "-" + randomUUID());
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

function probeModule(out: string): string {
  return fs.readFileSync(path.join(out, "msgonlyscope", "msg_only_two_probe.rs"), "utf8");
}

test("a catch region names the class it catches, not the module's last registered one", () => {
  const out = makeScratch("shape");
  generate(out);
  const probe = probeModule(out);

  // Each clause agrees with its own thrown class.
  expect(probe).toContain(
    "pub fn msg_only_two_probe_catch_first() -> Result<u32, MsgOnlyFirst>",
  );
  expect(probe).toContain("let __outcome: Result<(), MsgOnlyFirst> = (|| {");
  expect(probe).toContain(
    "pub fn msg_only_two_probe_catch_second() -> Result<u32, MsgOnlySecond>",
  );
  expect(probe).toContain("let __outcome1: Result<(), MsgOnlySecond> = (|| {");
}, 180_000);

test("a fallible block parameter takes the error type of the region that calls it", () => {
  const out = makeScratch("block");
  generate(out);
  const probe = probeModule(out);

  expect(probe).toContain(
    "pub fn msg_only_two_probe_run_in_region(run: Rc<RefCell<dyn FnMut() -> Result<(), MsgOnlyFirst> + 'static>>) -> Result<u32, MsgOnlyFirst>",
  );
  expect(probe).toContain("let __outcome2: Result<(), MsgOnlyFirst> = (|| {");
  // The block hands its own fault back unchanged; a module-keyed read used to
  // insert a conversion into the other class of the module.
  expect(probe).toContain(
    "let _ = MsgOnlyTwoProbe::msg_only_two_probe_fail_first()?;",
  );
  expect(probe).not.toContain("MsgOnlySecond::new(&format!");
}, 180_000);

test("the generated crate builds", () => {
  const out = makeScratch("build");
  generate(out);
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
