import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Kotlin TField smart cast: the receiver-root and field-mutability halves
 * (PIT-388).
 *
 * Kotlin smart-casts a read `recv.field` only when the field renders as a
 * `val` **and** the receiver chain's root local is a value Kotlin treats as
 * stable. The guard's flow proof (`recv.field != null`) supplies neither half
 * by itself: a `var` property is never smart-castable, a local this body
 * rebinds stops being stable from the rebinding onward, and a local a
 * capturing closure writes is unstable for the whole body.
 *
 * The driver asserts the *compiled* result rather than the emitted spelling.
 * kotlinc must accept the generated tree with zero errors and zero warnings,
 * and that single assertion fails in both directions: a negative shape that
 * keeps its bare dot is an error, while over-hardening an over-reach control
 * is an `unnecessary non-null assertion (!!)` warning. The mutation negative
 * control then writes the pre-fix predicate's output back into a copy of the
 * tree and asserts kotlinc rejects it, so the gate is shown to detect the
 * exact regression it guards rather than merely to agree with today's output.
 */

const root = path.resolve(import.meta.dir, "../..");
const scratch =
  Bun.env.BORING_SMARTCAST_TFIELD_OUT ??
  path.join(root, "out", "kotlin-smartcast-tfield", `test-${crypto.randomUUID()}`);

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

test("Kotlin TField smart cast respects the field half and the receiver-root half", async () => {
  fs.mkdirSync(scratch, { recursive: true });
  const generated = path.join(scratch, "gen");

  const haxe = observe(
    ["haxe", "tests/haxe/kotlin-smartcast-tfield/kotlin.hxml", "-D", `kotlin-output=${generated}`],
    root,
    "generate",
    scratch,
  );
  expect(haxe.code, `haxe generation failed: ${haxe.stderr || haxe.stdout}`).toBe(0);

  const files = (await Array.fromAsync(new Bun.Glob("**/*.kt").scan({ cwd: generated }))).sort();
  expect(files.length).toBeGreaterThan(0);
  fs.writeFileSync(
    path.join(scratch, "gen.sha256"),
    files
      .map(
        (file) =>
          `${new Bun.CryptoHasher("sha256").update(fs.readFileSync(path.join(generated, file))).digest("hex")}  ${file}`,
      )
      .join("\n") + "\n",
  );

  const source = fs.readFileSync(path.join(generated, "casee", "CaseEOps.kt"), "utf8");

  // Over-reach controls: Kotlin's own data flow proves both of these, so no
  // assertion may appear in them.
  expect(functionBody(source, "stableFinal"), "stableFinal must keep its plain dot").not.toContain("!!");
  expect(functionBody(source, "writeBeforeGuard"), "writeBeforeGuard must keep its plain dot").not.toContain("!!");

  // Negative controls: the unhardened spelling -- a bare dot on a nullable
  // field read -- must be gone from every one of them.
  for (const name of ["betweenWrite", "closureWrite", "varField"])
    expect(functionBody(source, name), `${name} must not emit a bare-dot call`).not.toMatch(/\.value\.magnitude\(\)/);

  const kotlinc = observe(
    ["kotlinc", ...files.map((file) => path.join(generated, file)), "-d", path.join(scratch, "fixture.jar")],
    root,
    "kotlinc",
    scratch,
  );
  const errors = diagnostics(kotlinc.stderr, "error");
  const warnings = diagnostics(kotlinc.stderr, "warning");
  expect(errors, `kotlinc errors:\n${kotlinc.stderr}`).toEqual([]);
  expect(warnings, `kotlinc warnings:\n${kotlinc.stderr}`).toEqual([]);
  expect(kotlinc.code, `kotlinc failed: ${kotlinc.stderr}`).toBe(0);

  // --- mutation negative control -----------------------------------------
  // Put the pre-fix predicate's output back: the bare dot in place of the
  // hardened access. Without this the driver would only show that the current
  // output compiles, not that the gate can see the regression.
  const mutant = path.join(scratch, "mutant");
  let hardened = 0;
  for (const file of files) {
    const target = path.join(mutant, file);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const text = fs.readFileSync(path.join(generated, file), "utf8");
    hardened += (text.match(/\.value!!\.magnitude\(\)/g) ?? []).length;
    hardened += (text.match(/\.value\?\.magnitude\(\)!!/g) ?? []).length;
    fs.writeFileSync(
      target,
      text.replaceAll(".value!!.magnitude()", ".value.magnitude()").replaceAll(".value?.magnitude()!!", ".value.magnitude()"),
    );
  }
  expect(hardened, "the three negative shapes must each carry a hardened access").toBe(3);

  const mutatedSource = fs.readFileSync(path.join(mutant, "casee", "CaseEOps.kt"), "utf8");
  for (const name of ["betweenWrite", "closureWrite", "varField"])
    expect(functionBody(mutatedSource, name), `${name} must have been reverted to the bare dot`).toMatch(
      /\.value\.magnitude\(\)/,
    );

  const mutated = observe(
    ["kotlinc", ...files.map((file) => path.join(mutant, file)), "-d", path.join(scratch, "mutant.jar")],
    root,
    "kotlinc-mutant",
    scratch,
  );
  expect(mutated.code, "the mutated tree must be rejected").not.toBe(0);
  const mutatedErrors = diagnostics(mutated.stderr, "error");
  expect(mutatedErrors.length, `mutated diagnostics:\n${mutated.stderr}`).toBeGreaterThanOrEqual(3);
  expect(mutated.stderr).toContain("only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver");
  expect(mutated.stderr).toContain("smart cast to 'Vec' is impossible");
  expect(mutated.stderr).toContain("mutated in a capturing closure");
  expect(mutated.stderr).toContain("mutable property that could be mutated concurrently");
}, 180_000);
