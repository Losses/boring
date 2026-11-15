import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * collectTypeModules regression: a recursive anonymous typedef must not send
 * the compilation-unit walk into unbounded recursion.
 *
 * Before commit e24cfefb the walk of a typedef body had no visited set, so
 * "typedef DiagRec = { var children:Array<DiagRec>; var leaf:Leaf; }" went
 * TType -> def.type -> TAnonymous -> field -> TInst(Array,[TType]) back to
 * the same TType until the stack overflowed and the whole compile exited
 * non-zero. The fix records the qualified declaration path of every expanded
 * typedef body, so a cycle is expanded once while the module and its
 * dependencies are still recorded.
 *
 * The fixture pairs a self-recursive typedef with a non-recursive dependency
 * (Leaf) and a mutually recursive pair (MutualA / MutualB). The TS and Kotlin
 * targets must both generate the recursive modules and their dependency,
 * which also proves the walk still reaches them after the cycle is cut.
 * Removing the visited set turns the same generation red, so the exit-0
 * assertion is the regression gate.
 */

const root = path.resolve(import.meta.dir, "..");
const scratch =
  Bun.env.BORING_RECURSIVE_TYPEDEF_OUT ??
  path.join(root, "out", "recursive-typedef", "test-" + randomUUID());

function generate(hxml: string, defs: string[]) {
  const result = Bun.spawnSync(["haxe", hxml, ...defs], {
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

test("recursive typedefs generate on ts and kotlin without a runaway walk", async () => {
  fs.mkdirSync(scratch, { recursive: true });

  // --- TypeScript: self-recursive plus mutually recursive typedefs ---------
  const ts = path.join(scratch, "ts");
  fs.mkdirSync(ts, { recursive: true });
  const tsRun = generate("tests/haxe/recursive-typedef/gen/ts.hxml", [
    "-D", "ts-output=" + ts + "/gen",
  ]);
  expect(tsRun.code, "ts generation failed:\n" + (tsRun.stderr || tsRun.stdout)).toBe(0);
  const tsModules = read(ts + "/gen/_GeneratedFiles.txt");
  expect(tsModules).toContain("probe/DiagRec.ts");
  expect(tsModules).toContain("probe/Leaf.ts");
  expect(tsModules).toContain("probe/MutualA.ts");
  expect(tsModules).toContain("probe/MutualB.ts");
  expect(tsModules).toContain("probe/SelfRoot.ts");
  expect(tsModules).toContain("probe/MutualRoot.ts");
  expect(read(ts + "/gen/probe/DiagRec.ts").length).toBeGreaterThan(0);
  expect(read(ts + "/gen/probe/Leaf.ts").length).toBeGreaterThan(0);

  // --- Kotlin: same fixture, unit table plus emitted tree ------------------
  const kt = path.join(scratch, "kt");
  fs.mkdirSync(kt, { recursive: true });
  const ktRun = generate("tests/haxe/recursive-typedef/gen/kotlin.hxml", [
    "-D", "kotlin-output=" + kt + "/gen",
    "-D", "kotlin-test-output=" + kt + "/gen-tests",
    "-D", "compilation_units_dump=" + kt + "/units.tsv",
  ]);
  expect(ktRun.code, "kotlin generation failed:\n" + (ktRun.stderr || ktRun.stdout)).toBe(0);
  const ktUnits = read(kt + "/units.tsv");
  expect(ktUnits).toContain("probe.DiagRec\tmain");
  expect(ktUnits).toContain("probe.Leaf\tmain");
  expect(ktUnits).toContain("probe.MutualA\tmain");
  expect(ktUnits).toContain("probe.MutualB\tmain");
  expect(ktUnits).toContain("probe.SelfRoot\tmain");
  expect(ktUnits).toContain("probe.MutualRoot\tmain");
  for (const name of ["DiagRec", "Leaf", "MutualA", "MutualB"]) {
    expect(fs.existsSync(kt + "/gen/probe/" + name + ".kt")).toBe(true);
  }
}, 600_000);
