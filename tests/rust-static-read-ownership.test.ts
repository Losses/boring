import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * A statement that reads the same handle-backed class static twice binds one
 * cloned read (StaticReadStatementScope). Every value read of that binding
 * must clone again: the generated Rust owns an Rc handle, so a bare second
 * read moves the same value twice and rustc rejects the crate (E0382).
 *
 * The first test locks the emitted shape; the second compiles and runs the
 * shaped crate, which is the step that rejected it before the fix.
 */

const root = path.resolve(import.meta.dir, "..");
const hxml = "tests/haxe/rust-static-read-ownership/gen/rust.hxml";

function makeScratch(tag: string): string {
  const dir = path.join(root, "out", "static-read-ownership", tag + "-" + randomUUID());
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function generate(out: string): void {
  const run = Bun.spawnSync(["haxe", hxml, "-D", "rust-output=" + out], { cwd: root, stdout: "pipe", stderr: "pipe" });
  expect(run.exitCode, run.stderr.toString()).toBe(0);
}

function addIntegrationTest(out: string, name: string, source: string): void {
  fs.mkdirSync(path.join(out, "tests"), { recursive: true });
  fs.writeFileSync(path.join(out, "tests", name + ".rs"), source);
  // Generated crates set autotests = false, so the test target is explicit.
  fs.appendFileSync(path.join(out, "Cargo.toml"), '\n[[test]]\nname = "' + name + '"\npath = "tests/' + name + '.rs"\n');
}

function cargoTest(out: string): { status: number; output: string } {
  const run = Bun.spawnSync(["cargo", "test", "--quiet"], { cwd: out, stdout: "pipe", stderr: "pipe" });
  return { status: run.exitCode, output: run.stdout.toString() + run.stderr.toString() };
}

test("two reads of one handle static clone the hoisted statement read", () => {
  const out = makeScratch("shape");
  generate(out);
  const src = fs.readFileSync(path.join(out, "probe", "static_read_ownership.rs"), "utf8");
  expect(src).toContain("let __static_read = { STATIC_READ_OWNERSHIP_INSTANCE.with(|__ta| __ta.clone()) };");
  expect(src).toContain("= __static_read.clone();");
  // A bare move of the hoisted binding is what rustc rejected with E0382.
  expect(src).not.toMatch(/=\s*__static_read;/);
}, 180000);

test("the generated crate reads the shared static twice, compiles and runs", () => {
  const out = makeScratch("runtime");
  generate(out);
  addIntegrationTest(
    out,
    "static_read_ownership_runtime",
    `use generated::probe::static_read_ownership::StaticReadOwnership;

#[test]
fn the_same_handle_is_read_twice_in_one_statement() {
    assert!(StaticReadOwnership::static_read_ownership_run());
}
`,
  );
  const run = cargoTest(out);
  expect(run.status, run.output).toBe(0);
}, 180000);
