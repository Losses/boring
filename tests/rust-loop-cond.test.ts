import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * A while condition is re-evaluated on every iteration, so a duplicated
 * static read must hoist inside the condition block; hoisting it before the
 * loop breaks the runtime semantics below.
 * (StaticReadLoop)
 *
 * The first test locks the emitted shape. The second one locks the runtime
 * semantics that the shape exists for: a null-initialized mutable class
 * static is re-assigned to a fresh object in the loop body, so a cached
 * handle hoisted before the loop never observes the new object. The
 * counterfactual moves the hoist before the loop and proves the result
 * differs, which is the difference the shape test alone cannot see.
 */

const root = path.resolve(import.meta.dir, "..");
const hxml = "tests/haxe/rust-loop-cond/gen/rust.hxml";

function makeScratch(tag: string): string {
  const dir = path.join(root, "out", "loop-cond", tag + "-" + randomUUID());
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function rustcVersion(): string {
  const run = Bun.spawnSync(["rustc", "--version"], { cwd: root, stdout: "pipe", stderr: "pipe" });
  expect(run.exitCode, run.stderr.toString()).toBe(0);
  return run.stdout.toString().trim();
}

function generate(out: string): void {
  const run = Bun.spawnSync(
    ["haxe", hxml, "-D", "rust-output=" + out],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  expect(run.exitCode, run.stderr.toString()).toBe(0);
}

function addIntegrationTest(out: string, name: string, source: string): void {
  fs.mkdirSync(path.join(out, "tests"), { recursive: true });
  fs.writeFileSync(path.join(out, "tests", name + ".rs"), source);
  // Generated crates set autotests = false, so the test target is explicit.
  fs.appendFileSync(path.join(out, "Cargo.toml"), '\n[[test]]\nname = "' + name + '"\npath = "tests/' + name + '.rs"\n');
}

function cargoTest(out: string): { status: number; output: string } {
  const version = rustcVersion();
  console.log("rustc before cargo test: " + version);
  const run = Bun.spawnSync(["cargo", "test", "--quiet"], { cwd: out, stdout: "pipe", stderr: "pipe" });
  return { status: run.exitCode, output: run.stdout.toString() + run.stderr.toString() };
}

/** Move the condition-block hoist before the loop, keeping the condition on
 * the cached local. This is the shape the StaticReadLoop fix rejects. */
function hoistConditionBeforeLoop(source: string): { source: string; hoistName: string } {
  const marker = "while { ";
  const start = source.indexOf(marker);
  expect(start).toBeGreaterThanOrEqual(0);
  const end = source.indexOf(" } {", start);
  expect(end).toBeGreaterThan(start);
  const block = source.slice(start + marker.length, end);
  const match = block.match(/^(let (__static_read\d*) = \{[\s\S]*?\};) ([\s\S]*)$/);
  expect(match).not.toBeNull();
  const hoist = match![1];
  const hoistName = match![2];
  const condition = match![3];
  const rewritten =
    source.slice(0, start) + hoist + "\n        while " + condition + " {" + source.slice(end + " } {".length);
  return { source: rewritten, hoistName };
}

test("while condition hoists duplicated static reads inside the condition block, not before the loop", () => {
  const scratch = makeScratch("shape");
  generate(scratch);

  const src = fs.readFileSync(path.join(scratch, "probe", "loop_cond.rs"), "utf8");
  const whileLine = src.split("\n").find((line) => line.includes("while "));
  expect(whileLine).toBeDefined();
  expect(whileLine!).toContain("while { let __static_read");
  // The hoist must not be a separate statement before the loop.
  const beforeLoop = src.slice(0, src.indexOf("while {"));
  expect(beforeLoop).not.toContain("let __static_read");
}, 180000);

test("a re-assigned nullable static is re-read every iteration, and the cached-hoist counterfactual differs", () => {
  // Null-initialized class static: declared T, Option-backed in Rust.
  const correctDir = makeScratch("reassign");
  generate(correctDir);
  const correctSrc = fs.readFileSync(path.join(correctDir, "probe", "reassign_loop.rs"), "utf8");
  // The null-initialized class static is re-assignable, so the
  // ThreadAffine realization keeps its slot in an owner-thread RefCell
  // (docs/specs/target-semantic-policy.md P-1a).
  expect(correctSrc).toContain("thread_local! {\n    pub static REASSIGN_LOOP_INSTANCE: RefCell<Option<Rc<RefCell<ReassignCounter>>>> = RefCell::new(None);\n}");
  expect(correctSrc).toContain("REASSIGN_LOOP_INSTANCE.with(|__ta| __ta.borrow().clone())");
  expect(correctSrc).toContain(".with(|c| *c.borrow_mut() = __rhs_value);");
  expect(correctSrc).toContain("Some(ReassignCounter::new(");
  expect(correctSrc).toContain("while { let __static_read");
  expect(correctSrc.slice(0, correctSrc.indexOf("while { let __static_read"))).not.toContain("let __static_read");

  addIntegrationTest(
    correctDir,
    "runtime_loop",
    `use generated::probe::reassign_loop::ReassignLoop;

#[test]
fn reassigned_static_terminates() {
    assert_eq!(ReassignLoop::reassign_loop_current_value(), 999, "the static starts null");
    assert_eq!(ReassignLoop::reassign_loop_run(), 300, "three reassignments end at value 0");
    assert_eq!(ReassignLoop::reassign_loop_current_value(), 0);
}
`,
  );
  const correct = cargoTest(correctDir);
  expect(correct.status, correct.output).toBe(0);

  // Counterfactual: the same generated crate with the static read hoisted
  // before the loop. The cached Rc handle points at the initial object, so
  // the condition never observes the body's reassignments.
  const counterfactualDir = makeScratch("reassign-counterfactual");
  generate(counterfactualDir);
  const counterfactualSrc = path.join(counterfactualDir, "probe", "reassign_loop.rs");
  const rewritten = hoistConditionBeforeLoop(fs.readFileSync(counterfactualSrc, "utf8"));
  fs.writeFileSync(counterfactualSrc, rewritten.source);
  const hoistAt = rewritten.source.indexOf("let " + rewritten.hoistName);
  const whileAt = rewritten.source.indexOf("while ");
  expect(hoistAt).toBeGreaterThanOrEqual(0);
  expect(whileAt).toBeGreaterThan(hoistAt);
  expect(rewritten.source.slice(hoistAt, whileAt)).not.toContain("while ");

  addIntegrationTest(
    counterfactualDir,
    "runtime_loop",
    `use generated::probe::reassign_loop::ReassignLoop;

#[test]
fn cached_handle_never_sees_reassignment() {
    assert_eq!(ReassignLoop::reassign_loop_current_value(), 999);
    assert_eq!(ReassignLoop::reassign_loop_run(), 101, "the cached handle keeps the initial object at value 3, so only the step guard ends the loop");
}
`,
  );
  const counterfactual = cargoTest(counterfactualDir);
  expect(counterfactual.status, counterfactual.output).toBe(0);
  // Passing @101 while the correct build passes @300 is the semantic
  // discrimination: the two shapes cannot both satisfy the same expectation.
}, 600000);
