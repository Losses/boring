import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Kotlin smart cast: the declaring-class / use-site compilation-unit clause
 * (PIT-389, R3-K).
 *
 * Kotlin smart-casts a "recv.field" read only when the declaring class and
 * the use site are compiled in the same module. A "public API" "val" property
 * read across a module boundary is never smart-castable, so a cross-unit read
 * must harden ("!!", "?.", or "?: throw") even when the field is "final",
 * has no getter, and the receiver is a stable "val" local.
 *
 * Before R3-K the "sameunit" clause degenerated to "is the declaring module
 * main?": Context.getLocalModule() at lowering time returns the meaningless
 * module std.UStringRT, which unitOf maps to main, so the clause was true for
 * every module and the cross-unit read kept its bare dot; kotlinc then
 * rejected the tree with "smart cast ... public API property declared in
 * different module" (the 7 PushInLineWideCapacityTest sites).
 *
 * The driver compiles the generated tree in two stages, mirroring the real
 * tiqian build: main.jar holds the business + runtime modules, tests.jar
 * holds the @:test module against main.jar on the classpath. The positive
 * tree must compile to tests.jar with zero errors; regenerating with
 * "-D kotlin_smartcast_drop=sameunit" drops the clause, restores the bare
 * dots, and kotlinc rejects tests.jar with the cross-module error, so the
 * gate is shown to detect the exact regression it guards.
 *
 * Warnings are deliberately not asserted zero: the shared runtime emits a
 * pre-existing "unnecessary !!" (StringTools), and the receiver-probe call
 * result carries a pre-existing "unnecessary !!" on its non-null Double
 * result, both unrelated to the smart-cast judgment and out of scope.
 */

const root = path.resolve(import.meta.dir, "../..");
const scratch =
  Bun.env.BORING_SMARTCAST_CROSSUNIT_OUT ??
  path.join(root, "out", "kotlin-smartcast-crossunit", "test-" + crypto.randomUUID());

type Observed = { code: number | null; stdout: string; stderr: string };

/** Runs one subprocess and records argv/cwd/status/both streams beside it. */
function observe(command: string[], cwd: string, label: string, out: string): Observed {
  const result = Bun.spawnSync(command, { cwd, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  fs.writeFileSync(path.join(out, label + ".argv"), cwd + "\n" + command.join(" ") + "\n");
  fs.writeFileSync(path.join(out, label + ".status"), (result.exitCode ?? -1) + "\n");
  fs.writeFileSync(path.join(out, label + ".stdout"), stdout);
  fs.writeFileSync(path.join(out, label + ".stderr"), stderr);
  return { code: result.exitCode, stdout, stderr };
}

function diagnostics(stream: string, kind: "error" | "warning"): string[] {
  return stream.split("\n").filter((line) => line.includes(": " + kind + ":"));
}

async function kt(dir: string): Promise<string[]> {
  return (await Array.fromAsync(new Bun.Glob("**/*.kt").scan({ cwd: dir }))).sort();
}

/** Generates the tree; the hxml contributes the fixtures, these defines the
 *  two-stage layout. */
function generate(genDir: string, testsDir: string, unitsPath: string, drop?: string): Observed {
  const args = [
    "haxe",
    "tests/haxe/kotlin-smartcast-crossunit/kotlin.hxml",
    "-D", "kotlin-output=" + genDir,
    "-D", "kotlin-test-output=" + testsDir,
    "-D", "runtime-import=boring.runtime",
    "-D", "runtime-emit=runtime",
    "-D", "compilation_units_dump=" + unitsPath,
  ];
  if (drop) args.push("-D", "kotlin_smartcast_drop=" + drop);
  return observe(args, root, "generate" + (drop ? "-drop" : ""), scratch);
}

/** Compiles main.jar (business + runtime) then tests.jar against it; returns
 *  the tests.jar observation. */
async function compileTwoStage(genDir: string, testsDir: string, label: string): Promise<Observed> {
  const genFiles = await kt(genDir);
  const mainFiles = genFiles
    .filter((f) => !f.startsWith("runtime/test/"))
    .map((f) => path.join(genDir, f));
  const runtimeTestFiles = genFiles
    .filter((f) => f.startsWith("runtime/test/"))
    .map((f) => path.join(genDir, f));
  const main = observe(
    ["kotlinc", "-J-Xmx4g", ...mainFiles, "-d", path.join(scratch, label + "-main.jar")],
    root,
    label + "-kotlinc-main",
    scratch,
  );
  expect(main.code, "main.jar compile failed:\n" + main.stderr).toBe(0);

  const testGenFiles = (await kt(testsDir)).map((f) => path.join(testsDir, f));
  const testFiles = [...runtimeTestFiles, ...testGenFiles];
  return observe(
    ["kotlinc", "-J-Xmx4g", "-classpath", path.join(scratch, label + "-main.jar"), ...testFiles, "-d", path.join(scratch, label + "-tests.jar")],
    root,
    label + "-kotlinc-tests",
    scratch,
  );
}

test("Kotlin smart cast hardens a cross-unit public-API val read, and only then", async () => {
  fs.mkdirSync(scratch, { recursive: true });

  const verifyGen = path.join(scratch, "verify", "gen");
  const verifyTests = path.join(scratch, "verify", "gen-tests");
  const verifyUnits = path.join(scratch, "verify", "units.tsv");
  const haxe = generate(verifyGen, verifyTests, verifyUnits);
  expect(haxe.code, "haxe generation failed:\n" + (haxe.stderr || haxe.stdout)).toBe(0);

  const units = fs.readFileSync(verifyUnits, "utf8");
  expect(units).toContain("xcasee.CrossunitAnno\ttests");
  expect(units).toContain("casee.Holder\tmain");
  expect(units).toContain("casee.Support\tmain");
  expect(units).toContain("casee.Vec\tmain");

  const source = fs.readFileSync(path.join(verifyTests, "xcasee", "CrossunitAnno.kt"), "utf8");
  // No cross-unit read may keep its bare dot, in either the argument or the
  // receiver shape.
  expect(source, "must not emit a bare-dot argument").not.toMatch(/useVec\(c\.value\)/);
  expect(source, "must not emit a bare-dot receiver").not.toMatch(/\.value\.magnitude\(\)/);
  // And the hardened spellings must be present: argument, receiver, safe-call.
  expect(source).toContain('c.value ?: throw IllegalArgumentException("argument is null")');
  expect(source).toContain("c.value!!");
  expect(source).toContain("c.value?.");

  const positive = await compileTwoStage(verifyGen, verifyTests, "verify");
  expect(diagnostics(positive.stderr, "error"), "tests.jar errors:\n" + positive.stderr).toEqual([]);
  expect(positive.code, "tests.jar failed:\n" + positive.stderr).toBe(0);

  // --- mutation negative control -----------------------------------------
  const dropGen = path.join(scratch, "drop", "gen");
  const dropTests = path.join(scratch, "drop", "gen-tests");
  const dropUnits = path.join(scratch, "drop", "units.tsv");
  const dropHaxe = generate(dropGen, dropTests, dropUnits, "sameunit");
  expect(dropHaxe.code, "haxe drop generation failed:\n" + (dropHaxe.stderr || dropHaxe.stdout)).toBe(0);

  const dropSource = fs.readFileSync(path.join(dropTests, "xcasee", "CrossunitAnno.kt"), "utf8");
  expect(dropSource, "dropped sameunit must restore the bare-dot argument").toMatch(/useVec\(c\.value\)/);
  expect(dropSource, "dropped sameunit must restore the bare-dot receiver").toMatch(/\.value\.magnitude\(\)/);

  const negative = await compileTwoStage(dropGen, dropTests, "drop");
  expect(negative.code, "the dropped tree must be rejected:\n" + negative.stderr).not.toBe(0);
  expect(negative.stderr).toContain("public API property declared in different module");
}, 300_000);

