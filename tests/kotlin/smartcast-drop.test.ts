import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Kotlin smart-cast clause ablation (GP-ABLATE, WBS §0.3).
 *
 * `smartCastableSubject` is a conjunction of clauses, each gated by
 * `-D kotlin_smartcast_drop=<clause>`: dropping a clause re-emits the
 * unhardened spelling -- the bare dot on a nullable field read -- and kotlinc
 * surfaces the exact error that clause prevents. This driver asserts the
 * *compiled* result, not just rc, and requires the error-text fragment, so it
 * detects both directions of every clause.
 *
 * Clause tally (see KotlinExpr.hx smartCastableSubject doc table):
 *   val           bidirectional  rc 0 vs !=0  "mutable property"
 *   closurewrite  bidirectional  rc 0 vs !=0  "mutated in a capturing closure"
 *   rebind        bidirectional  rc 0 vs !=0  "only safe (?.) ... nullable receiver"
 *   open          vacuous         rc 0 vs 0    (backend never emits `open`)
 *   getter        vacuous         rc 0 vs 0    (`var X(get,never)` is caught by
 *                                               `val` first; `final X(get,never)`
 *                                               is a Haxe syntax error)
 *   sameunit      (deferred: needs two-stage cross-module compilation)
 *
 * One run writes `<scratch>/rc-table.md`, the rc table the acceptance
 * report asks for.
 */

const root = path.resolve(import.meta.dir, "../..");
const scratch =
  Bun.env.BORING_SMARTCAST_DROP_OUT ??
  path.join(root, "out", "kotlin-smartcast-drop", `test-${crypto.randomUUID()}`);

type Observed = { code: number | null; stdout: string; stderr: string };

/** Runs one subprocess and records argv/cwd/status/both streams beside it. */
function observe(command: string[], cwd: string, label: string, out: string): Observed {
  const result = Bun.spawnSync(command, { cwd, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  fs.writeFileSync(path.join(out, `${label}.argv`), `${cwd}\n${command.join(" ")}\n`);
  fs.writeFileSync(path.join(out, `${label}.status`), `${result.exitCode ?? -1}\n`);
  fs.writeFileSync(path.join(out, `${label}.stdout`), stdout);
  fs.writeFileSync(path.join(out, `${label}.stderr`), stderr);
  return { code: result.exitCode, stdout, stderr };
}

function diagnostics(stream: string, kind: "error" | "warning"): string[] {
  return stream.split("\n").filter((line) => line.includes(`: ${kind}:`));
}

/**
 * The text of one generated function body. Brace matching is enough for
 * generated Kotlin: these functions carry no brace inside a literal.
 */
function functionBody(source: string, name: string): string {
  const signature = source.indexOf(`fun ${name}(`);
  expect(signature, `generated Kotlin declares ${name}`).toBeGreaterThanOrEqual(0);
  const open = source.indexOf("{", signature);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === "{") depth++;
    else if (source[i] === "}") {
      depth--;
      if (depth === 0) return source.slice(open, i + 1);
    }
  }
  throw new Error(`unterminated body for ${name}`);
}

type Clause = {
  name: string; // the -D kotlin_smartcast_drop value
  fn: string; // the probe function name
  defaultBareDot: boolean; // default spelling is the bare dot (over-reach) or hardened (negative)
  dropRc0: boolean; // drop keeps rc=0 (vacuous) or flips to !=0 (bidirectional)
  errorFrag: string | null; // error-text fragment asserted on drop !=0
};

const CLAUSES: Clause[] = [
  { name: "val", fn: "valField", defaultBareDot: false, dropRc0: false, errorFrag: "mutable property that could be mutated concurrently" },
  { name: "closurewrite", fn: "closureRebind", defaultBareDot: false, dropRc0: false, errorFrag: "mutated in a capturing closure" },
  { name: "rebind", fn: "rebindBetween", defaultBareDot: false, dropRc0: false, errorFrag: "only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver" },
  { name: "open", fn: "stableOpen", defaultBareDot: true, dropRc0: true, errorFrag: null },
  { name: "getter", fn: "getterOnly", defaultBareDot: false, dropRc0: true, errorFrag: null },
];

test("each smart-cast clause ablates to the error it prevents", async () => {
  fs.mkdirSync(scratch, { recursive: true });
  const rcRows: string[] = ["| clause | direction | rc | errors |", "|---|---|---|---|"];

  // --- default (all clauses present) -------------------------------------
  const generated = path.join(scratch, "gen-default");
  const haxe = observe(
    ["haxe", "tests/haxe/kotlin-smartcast-drop/kotlin.hxml", "-D", `kotlin-output=${generated}`],
    root,
    "generate-default",
    scratch,
  );
  expect(haxe.code, `haxe generation failed: ${haxe.stderr || haxe.stdout}`).toBe(0);

  const files = (await Array.fromAsync(new Bun.Glob("**/*.kt").scan({ cwd: generated }))).sort();
  expect(files.length).toBeGreaterThan(0);
  fs.writeFileSync(
    path.join(scratch, "gen-default.sha256"),
    files
      .map((f) => `${new Bun.CryptoHasher("sha256").update(fs.readFileSync(path.join(generated, f))).digest("hex")}  ${f}`)
      .join("\n") + "\n",
  );

  const source = fs.readFileSync(path.join(generated, "casee", "SmartcastDrop.kt"), "utf8");
  for (const c of CLAUSES) {
    const body = functionBody(source, c.fn);
    if (c.defaultBareDot) {
      expect(body, `${c.fn} default must keep its plain dot`).toMatch(/\.value\.magnitude\(\)/);
      expect(body, `${c.fn} default must not harden`).not.toContain("!!");
    } else {
      expect(body, `${c.fn} default must harden (no bare dot)`).not.toMatch(/\.value\.magnitude\(\)/);
      expect(body, `${c.fn} default must carry a !!`).toContain("!!");
    }
  }

  const kotlinc = observe(
    ["kotlinc", ...files.map((f) => path.join(generated, f)), "-d", path.join(scratch, "default.jar")],
    root,
    "kotlinc-default",
    scratch,
  );
  const errors = diagnostics(kotlinc.stderr, "error");
  const warnings = diagnostics(kotlinc.stderr, "warning");
  expect(errors, `default kotlinc errors:\n${kotlinc.stderr}`).toEqual([]);
  expect(warnings, `default kotlinc warnings:\n${kotlinc.stderr}`).toEqual([]);
  expect(kotlinc.code, `default kotlinc failed: ${kotlinc.stderr}`).toBe(0);
  rcRows.push("| (all) | present | 0 | 0 |");

  // --- each clause, dropped ---------------------------------------------
  for (const c of CLAUSES) {
    const dropped = path.join(scratch, `gen-drop-${c.name}`);
    const haxeDrop = observe(
      ["haxe", "tests/haxe/kotlin-smartcast-drop/kotlin.hxml", "-D", `kotlin-output=${dropped}`, "-D", `kotlin_smartcast_drop=${c.name}`],
      root,
      `generate-drop-${c.name}`,
      scratch,
    );
    expect(haxeDrop.code, `haxe drop=${c.name} generation failed: ${haxeDrop.stderr || haxeDrop.stdout}`).toBe(0);

    const dropFiles = (await Array.fromAsync(new Bun.Glob("**/*.kt").scan({ cwd: dropped }))).sort();
    const dropSource = fs.readFileSync(path.join(dropped, "casee", "SmartcastDrop.kt"), "utf8");
    const dropBody = functionBody(dropSource, c.fn);

    const kotlincDrop = observe(
      ["kotlinc", ...dropFiles.map((f) => path.join(dropped, f)), "-d", path.join(scratch, `drop-${c.name}.jar`)],
      root,
      `kotlinc-drop-${c.name}`,
      scratch,
    );
    const dropErrors = diagnostics(kotlincDrop.stderr, "error");

    if (c.dropRc0) {
      if (c.defaultBareDot) {
        expect(dropBody, `drop=${c.name} must keep its plain dot`).toMatch(/\.value\.magnitude\(\)/);
      } else {
        expect(dropBody, `drop=${c.name} must stay hardened`).not.toMatch(/\.value\.magnitude\(\)/);
      }
      expect(dropErrors, `drop=${c.name} must still have no errors:\n${kotlincDrop.stderr}`).toEqual([]);
      expect(kotlincDrop.code, `drop=${c.name} must still compile (vacuous): ${kotlincDrop.stderr}`).toBe(0);
      rcRows.push(`| ${c.name} | dropped | 0 | 0 |`);
    } else {
      expect(dropBody, `drop=${c.name} must emit the bare dot`).toMatch(/\.value\.magnitude\(\)/);
      expect(kotlincDrop.code, `drop=${c.name} must be rejected: ${kotlincDrop.stderr}`).not.toBe(0);
      expect(dropErrors.length, `drop=${c.name} diagnostics:\n${kotlincDrop.stderr}`).toBeGreaterThanOrEqual(1);
      expect(kotlincDrop.stderr, `drop=${c.name} error text`).toContain(c.errorFrag!);
      rcRows.push(`| ${c.name} | dropped | !=0 | ${dropErrors.length} |`);
    }
  }

  fs.writeFileSync(path.join(scratch, "rc-table.md"), rcRows.join("\n") + "\n");
}, 600_000);
