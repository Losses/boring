import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * A while condition is re-evaluated on every iteration, so a duplicated
 * static read must hoist inside the condition block, not before the loop.
 * (StaticReadLoop)
 *
 * This locks the emitted shape, not a runtime difference: the clone is an
 * Rc handle to the same RefCell, so a body that only mutates the object in
 * place behaves identically under either form. A discriminating case needs
 * the body to reassign the static, which the current subset cannot express.
 */

const root = path.resolve(import.meta.dir, "..");
const scratch =
  Bun.env.BORING_LOOP_COND_OUT ??
  path.join(root, "out", "loop-cond", "test-" + randomUUID());

test("while condition hoists duplicated static reads inside the condition block, not before the loop", () => {
  fs.mkdirSync(scratch, { recursive: true });
  const run = Bun.spawnSync(
    ["haxe", "tests/haxe/rust-loop-cond/gen/rust.hxml", "-D", "rust-output=" + scratch],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  expect(run.exitCode, run.stderr.toString()).toBe(0);

  const src = fs.readFileSync(path.join(scratch, "probe", "loop_cond.rs"), "utf8");
  const whileLine = src.split("\n").find((line) => line.includes("while "));
  expect(whileLine).toBeDefined();
  expect(whileLine!).toContain("while { let __static_read");
  // The hoist must not be a separate statement before the loop.
  const beforeLoop = src.slice(0, src.indexOf("while {"));
  expect(beforeLoop).not.toContain("let __static_read");
}, 180000);
