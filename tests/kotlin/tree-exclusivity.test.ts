import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Kotlin output trees hold one copy per module.
 *
 * The unit decision routes a module into the shipping tree or the test tree,
 * and both trees are reused across generation runs. A module whose unit
 * changes between runs (here: test code alone references it in the first run,
 * and a shipping-tree module references it in the second) must therefore
 * leave no copy in the tree it left: a consumer that compiles the main output
 * together with the test root reports a redeclaration for every type the file
 * declares. tiqian hit exactly that shape when `@:mainOnly` moved
 * `org.tiqian.shaping.ReplayableFontBackend` from gen-tests into gen and the
 * earlier copy stayed behind.
 */

const root = path.resolve(import.meta.dir, "../..");
const out = path.join(root, "out", "kotlin-tree-exclusivity");
const hxml = "tests/haxe/kotlin-tree-exclusivity/kotlin.hxml";

type Run = { code: number | null; output: string };

/** Generates both trees from the given roots, reusing the trees across runs. */
function generate(roots: string[]): Run {
  const args = [
    "haxe",
    hxml,
    "-D",
    "kotlin-output=" + path.join(out, "gen"),
    "-D",
    "kotlin-test-output=" + path.join(out, "gen-tests"),
  ];
  for (const name of roots) {
    args.push(name);
  }
  const result = Bun.spawnSync(args, { cwd: root, stdout: "pipe", stderr: "pipe" });
  return {
    code: result.exitCode,
    output: result.stdout.toString() + result.stderr.toString(),
  };
}

function generated(relative: string): boolean {
  return fs.existsSync(path.join(out, relative));
}

test("a module whose unit changes leaves no copy in the tree it left", () => {
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(path.join(out, "gen"), { recursive: true });
  fs.mkdirSync(path.join(out, "gen-tests"), { recursive: true });

  const testRun = generate(["trees.SharedTest"]);
  expect(testRun.code, "run 1: " + testRun.output).toBe(0);
  expect(generated("gen-tests/trees/Shared.kt"), "run 1 routes Shared into the test tree").toBe(true);
  expect(generated("gen/trees/Shared.kt"), "run 1 keeps Shared out of the main tree").toBe(false);

  const mainRun = generate(["trees.SharedTest", "trees.Entry"]);
  expect(mainRun.code, "run 2: " + mainRun.output).toBe(0);
  expect(generated("gen/trees/Shared.kt"), "run 2 routes Shared into the main tree").toBe(true);
  expect(generated("gen-tests/trees/Shared.kt"), "run 2 leaves no copy in the test tree").toBe(false);
}, 120_000);
