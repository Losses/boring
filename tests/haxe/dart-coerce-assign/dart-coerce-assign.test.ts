import { expect, test } from "bun:test";

// Dart Argument coercion (P4): a Null<Int> value passed into a non-null Int
// parameter must be hardened with `!`, on three argument shapes:
//
//   * a method-call result   (callArgTexts path, "call"),
//   * a nullable field read  (callArgTexts path, "field"),
//   * a nullable local read  (callArgTexts path, "local").
//
// The positive tree emits `(this.nullableInt())!`, `(this.nullableField)!`
// and `x!` on those targets and `dart analyze` accepts them. The ablation
// arm regenerates with -D dart_coerce_ablate=Argument, which skips the
// Argument coercion and leaves the bare nullable value; `dart analyze` then
// rejects it with `argument_type_not_assignable`. The two compile arms must
// differ (GP-ABLATE). Assertions name the emitted form (the `!` extraction)
// rather than merely "it compiles" (LAYERED-VERIFICATION).
const root = `${import.meta.dir}/../../..`;
const out =
  Bun.env.BORING_DART_COERCE_ASSIGN_OUT ??
  `${root}/out/dart-coerce-assign/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;
const generatedAblate = `${out}/gen-ablate`;
const testGenerated = `${out}/gen-tests`;
const testGeneratedAblate = `${out}/gen-tests-ablate`;

type Result = { code: number | null; stdout: string; stderr: string };

function run(command: Array<string>): Result {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  return { code: result.exitCode, stdout: result.stdout.toString(), stderr: result.stderr.toString() };
}

/** The body of one `int name()` declaration, up to its closing brace. */
function functionBody(source: string, name: string): string {
  const start = source.indexOf(`int ${name}(`);
  if (start < 0) throw new Error(`no emitted function ${name}`);
  const open = source.indexOf("{", start);
  let depth = 0;
  for (let index = open; index < source.length; index++) {
    if (source[index] === "{") depth++;
    if (source[index] === "}") {
      depth--;
      if (depth === 0) return source.slice(open, index + 1);
    }
  }
  throw new Error(`unterminated body of ${name}`);
}

// The coercion form differs per argument shape: a bare local promotes to
// `x!` while a non-bare argument (a call or a field read) parenthesizes
// before the postfix: `(this.nullableInt())!`.
const coerced: Record<string, string> = {
  passCall: "(this.nullableInt())!",
  passField: "(this.nullableField)!",
  passLocal: "x!",
};

test("nullable values passed as non-null Int arguments harden on every shape", async () => {
  await Bun.$`mkdir -p ${out}`;

  // positive arm
  const gen = run([
    "haxe", "tests/haxe/dart-coerce-assign/dart.hxml",
    "-D", `dart-output=${generated}`,
    "-D", `dart-test-output=${testGenerated}`,
  ]);
  expect(gen.code, `haxe generation failed: ${gen.stderr || gen.stdout}`).toBe(0);

  const files = Array.from(new Bun.Glob("**/*.dart").scanSync({ cwd: generated })).sort();
  expect(files.length).toBeGreaterThan(0);

  const normal = await Bun.file(`${generated}/lib/assigning/assign_cases.dart`).text();
  for (const name of Object.keys(coerced))
    expect(
      functionBody(normal, name),
      `${name} must harden its nullable argument with !`,
    ).toContain(coerced[name]);

  // ablation arm
  const genAblate = run([
    "haxe", "tests/haxe/dart-coerce-assign/dart.hxml",
    "-D", "dart_coerce_ablate=Argument",
    "-D", `dart-output=${generatedAblate}`,
    "-D", `dart-test-output=${testGeneratedAblate}`,
  ]);
  expect(genAblate.code, `ablate generation failed: ${genAblate.stderr || genAblate.stdout}`).toBe(0);

  const ablate = await Bun.file(`${generatedAblate}/lib/assigning/assign_cases.dart`).text();
  for (const name of Object.keys(coerced))
    expect(
      functionBody(ablate, name),
      `${name} must keep its bare nullable value when ablated`,
    ).not.toContain(coerced[name]);

  // compile arms (GP-ABLATE): `dart analyze` is the reject shell
  const dart = Bun.which("dart");
  if (dart === null) {
    process.stderr.write("dart not on PATH: compile stage environment-not-reached");
    return;
  }

  const normalAnalyze = run([dart, "analyze", "--no-fatal-warnings", generated]);
  expect(normalAnalyze.code, `positive dart analyze must accept the hardened tree`).toBe(0);

  const ablateAnalyze = run([dart, "analyze", "--no-fatal-warnings", generatedAblate]);
  expect(ablateAnalyze.code, `ablate dart analyze must reject the bare nullable argument`).not.toBe(0);
  expect(
    ablateAnalyze.stdout,
    `ablate dart analyze must name the type mismatch`,
  ).toContain("argument_type_not_assignable");
}, 180_000);
