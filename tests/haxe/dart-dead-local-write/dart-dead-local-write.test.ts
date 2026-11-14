import { expect, test } from "bun:test";

// Dart dead-local elimination (write guard): a local that is declared with an
// initializer, written afterwards and never read must keep its declaration.
// Dropping the declaration leaves the later write naming a variable that no
// longer exists, and `dart analyze` rejects the tree with undefined_identifier
// (observed downstream as "Setter not found: 'gs'").
//
// The positive arm emits `var gs = seed;` and `dart analyze` accepts the tree.
// The ablation arm regenerates with -D dart_dead_local_ablate=WriteGuard, which
// disables the guard: the declaration disappears while the write stays, and
// `dart analyze` rejects the tree. The two compile arms must differ (GP-ABLATE).
// A local that is neither read nor written is still dropped in both arms, so the
// fixture also pins the elimination the guard must not disable.
const root = `${import.meta.dir}/../../..`;
const out =
  Bun.env.BORING_DART_DEAD_LOCAL_OUT ??
  `${root}/out/dart-dead-local-write/test-${crypto.randomUUID()}`;
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

test("a written-but-never-read local keeps its declaration", async () => {
  await Bun.$`mkdir -p ${out}`;

  // positive arm
  const gen = run([
    "haxe", "tests/haxe/dart-dead-local-write/dart.hxml",
    "-D", `dart-output=${generated}`,
    "-D", `dart-test-output=${testGenerated}`,
  ]);
  expect(gen.code, `haxe generation failed: ${gen.stderr || gen.stdout}`).toBe(0);

  const normal = await Bun.file(`${generated}/lib/deadlocalwrite/write_only_local.dart`).text();
  const loop = functionBody(normal, "writeInLoop");
  expect(loop, `writeInLoop must keep the declaration:\n${loop}`).toContain("var gs = seed;");
  expect(loop, `writeInLoop must keep the write:\n${loop}`).toContain("gs = n;");
  const closure = functionBody(normal, "writeInClosure");
  expect(closure, `writeInClosure must keep the declaration:\n${closure}`).toContain("var gs = seed;");
  // The elimination still drops a declaration that is neither read nor written.
  const dead = functionBody(normal, "deadDeclaration");
  expect(dead, `deadDeclaration must drop the unread local:\n${dead}`).not.toContain("unused");

  // ablation arm
  const genAblate = run([
    "haxe", "tests/haxe/dart-dead-local-write/dart.hxml",
    "-D", "dart_dead_local_ablate=WriteGuard",
    "-D", `dart-output=${generatedAblate}`,
    "-D", `dart-test-output=${testGeneratedAblate}`,
  ]);
  expect(genAblate.code, `ablate generation failed: ${genAblate.stderr || genAblate.stdout}`).toBe(0);

  const ablate = await Bun.file(`${generatedAblate}/lib/deadlocalwrite/write_only_local.dart`).text();
  const ablateLoop = functionBody(ablate, "writeInLoop");
  expect(ablateLoop, `ablated writeInLoop must drop the declaration:\n${ablateLoop}`).not.toContain("var gs");
  expect(ablateLoop, `ablated writeInLoop must keep the write:\n${ablateLoop}`).toContain("gs = n;");

  // compile arms (GP-ABLATE): `dart analyze` is the reject shell
  const dart = Bun.which("dart");
  if (dart === null) {
    process.stderr.write("dart not on PATH: compile stage environment-not-reached");
    return;
  }

  const normalAnalyze = run([dart, "analyze", "--no-fatal-warnings", generated]);
  expect(normalAnalyze.code, `positive dart analyze must accept the tree:\n${normalAnalyze.stdout}`).toBe(0);
  expect(
    normalAnalyze.stdout,
    `positive dart analyze must not report an undefined name:\n${normalAnalyze.stdout}`,
  ).not.toContain("undefined_identifier");

  const ablateAnalyze = run([dart, "analyze", "--no-fatal-warnings", generatedAblate]);
  expect(ablateAnalyze.code, `ablate dart analyze must reject the tree:\n${ablateAnalyze.stdout}`).not.toBe(0);
  expect(
    ablateAnalyze.stdout,
    `ablate dart analyze must name the undefined write target:\n${ablateAnalyze.stdout}`,
  ).toContain("undefined_identifier");
}, 180_000);
