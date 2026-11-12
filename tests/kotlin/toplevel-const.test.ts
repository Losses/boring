import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Kotlin top-level constants (features/10 field form).
 *
 * Haxe has no constant at module scope: a `static final` hangs off a class, and
 * the Kotlin target rendered every one of them as an `object` member. The
 * published engine declares two constants at file top level and its consumers
 * import the names directly
 * (`import org.tiqian.shaping.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE`), so an
 * object member is source-incompatible with the published API.
 *
 * `@:topLevel` on a `static final` moves the declaration to the file top
 * level. The fixture holds both shapes side by side: `MarkedConsts` extracts,
 * `UnmarkedConsts` keeps its object, and one cross-package consumer reads
 * both. The test fails if the marker stops extracting, if the default shape
 * changes, or if one declaration appears in both shapes.
 */

const root = path.resolve(import.meta.dir, "../..");
const scratch =
  Bun.env.BORING_TOPLEVEL_CONST_OUT ?? path.join(root, "out", "kotlin-toplevel-const", `test-${crypto.randomUUID()}`);

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

/** The file top-level `const val` declarations of one generated file. */
function topLevelConsts(source: string): string[] {
  return source.split("\n").filter((line) => /^(private )?const val /.test(line));
}

/** Rewrites a top-level constant file into the pre-fix object member shape. */
function asObjectMembers(source: string, holder: string): string {
  const pkg = source.split("\n").find((line) => line.startsWith("package ")) ?? "";
  const body = topLevelConsts(source).map((line) => `    ${line}`);
  return `${pkg}\n\nobject ${holder} {\n${body.join("\n")}\n}\n`;
}

test("Kotlin top-level constants: the marker extracts and the default keeps the object", async () => {
  fs.mkdirSync(scratch, { recursive: true });
  const generated = path.join(scratch, "gen");

  const haxe = observe(
    ["haxe", "tests/haxe/kotlin-toplevel-const/kotlin.hxml", "-D", `kotlin-output=${generated}`],
    root,
    "generate",
    scratch,
  );
  expect(haxe.code, `haxe generation failed: ${haxe.stderr || haxe.stdout}`).toBe(0);

  const files = (await Array.fromAsync(new Bun.Glob("**/*.kt").scan({ cwd: generated }))).sort();
  expect(files.length).toBeGreaterThan(0);

  const marked = fs.readFileSync(path.join(generated, "toplevelconst", "MarkedConsts.kt"), "utf8");
  const unmarked = fs.readFileSync(path.join(generated, "toplevelconst", "UnmarkedConsts.kt"), "utf8");
  const consumer = fs.readFileSync(path.join(generated, "toplevelconst", "consumer", "ConstConsumer.kt"), "utf8");

  // Criterion 1: the marked holder contributes no namespace. Every constant is
  // a file top-level declaration, and no object member survives beside it.
  expect(marked).not.toContain("object MarkedConsts");
  expect(topLevelConsts(marked)).toEqual([
    'const val PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE: String = "PlatformMultiFaceStringDraw"',
    'const val COVERAGE_ISSUE: String = "UnverifiedDisplaySubstitutionCoverage"',
    "const val FLOAT_CONST: Double = 16.0",
    "private const val PRIVATE_CONST: Int = 7",
  ]);
  expect(marked).not.toMatch(/^[ \t]+const val /m);

  // Criterion 2: the unmarked control keeps the default shape. One object, the
  // same declarations as members, nothing at the file top level.
  expect(unmarked).toContain("object UnmarkedConsts {");
  expect(topLevelConsts(unmarked)).toEqual([]);
  expect(unmarked).toContain('    const val PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE: String = "PlatformMultiFaceStringDraw"');
  expect(unmarked).toContain("    private const val PRIVATE_CONST: Int = 7");

  // Criterion 3: a cross-package consumer imports the constant name itself and
  // reads it unqualified. The unmarked constant keeps its holder qualifier.
  expect(consumer).toContain("import toplevelconst.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE");
  expect(consumer).toContain("import toplevelconst.COVERAGE_ISSUE");
  expect(consumer).toContain("import toplevelconst.FLOAT_CONST");
  expect(consumer).toContain("return PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE");
  expect(consumer).toContain("return UnmarkedConsts.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE");
  expect(consumer).not.toContain("MarkedConsts.");

  // Criterion 4: kotlinc resolves the top-level imports, with no diagnostics.
  const kotlinc = observe(
    ["kotlinc", ...files.map((file) => path.join(generated, file)), "-d", path.join(scratch, "probe.jar")],
    root,
    "kotlinc",
    scratch,
  );
  expect(diagnostics(kotlinc.stderr, "error"), `kotlinc errors:\n${kotlinc.stderr}`).toEqual([]);
  expect(diagnostics(kotlinc.stderr, "warning"), `kotlinc warnings:\n${kotlinc.stderr}`).toEqual([]);
  expect(kotlinc.code, `kotlinc failed: ${kotlinc.stderr}`).toBe(0);

  // --- mutation negative control -----------------------------------------
  // Put the pre-fix shape back: the same constants as object members while the
  // consumer keeps its top-level imports. The import must then fail to
  // resolve, so the compile assertion above detects the exact regression it
  // guards.
  const mutant = path.join(scratch, "mutant");
  for (const file of files) {
    const target = path.join(mutant, file);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const text = fs.readFileSync(path.join(generated, file), "utf8");
    fs.writeFileSync(target, file.endsWith("MarkedConsts.kt") ? asObjectMembers(text, "MarkedConsts") : text);
  }
  const mutated = observe(
    ["kotlinc", ...files.map((file) => path.join(mutant, file)), "-d", path.join(scratch, "mutant.jar")],
    root,
    "kotlinc-mutant",
    scratch,
  );
  expect(mutated.code, "the mutated tree must be rejected").not.toBe(0);
  expect(mutated.stderr).toContain("unresolved reference");
}, 180_000);
