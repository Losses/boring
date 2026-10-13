import { expect, test } from "bun:test";

// Kotlin Assignment coercion (P2.3): a Null<Int> value assigned to a
// non-null Int target must be hardened with !!, on three targets:
//
//   * a non-null local declaration   (extractAtDecl path, role "local"),
//   * a non-null array element write   (assignValueText, role "array"),
//   * a non-null field write           (assignValueText, role "field").
//
// The positive tree emits `this.nullableInt()!!` on every target and
// kotlinc accepts it. The ablation arm regenerates with
// -D kotlin_coerce_ablate=Assignment, which skips the Assignment coercion
// and leaves the bare nullable value; kotlinc then rejects it with a type
// mismatch. The two compile arms must differ (GP-ABLATE). Assertions name
// the emitted form (the `!!` extraction) rather than merely "it compiles"
// (LAYERED-VERIFICATION).
const root = `${import.meta.dir}/../../..`;
const out =
  Bun.env.BORING_COERCE_ASSIGN_OUT ??
  `${root}/out/kotlin-coerce-assign/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;
const generatedAblate = `${out}/gen-ablate`;

type Result = { code: number | null; stdout: string; stderr: string };

function run(command: Array<string>): Result {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  return { code: result.exitCode, stdout: result.stdout.toString(), stderr: result.stderr.toString() };
}

/** The body of one `fun name(...)` declaration, up to its closing brace. */
function functionBody(source: string, name: string): string {
  const start = source.indexOf(`fun ${name}(`);
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

test("nullable values assigned to non-null locals, array elements and fields extract on every target", async () => {
  await Bun.$`mkdir -p ${out}`;

  // positive arm
  const gen = run([
    "haxe", "tests/haxe/kotlin-coerce-assign/kotlin.hxml",
    "-D", `kotlin-output=${generated}`,
  ]);
  expect(gen.code, `haxe generation failed: ${gen.stderr || gen.stdout}`).toBe(0);

  const files = Array.from(new Bun.Glob("**/*.kt").scanSync({ cwd: generated })).sort();
  expect(files.length).toBeGreaterThan(0);

  const normal = await Bun.file(`${generated}/assigning/AssignCases.kt`).text();
  for (const name of ["assignLocal", "assignArray", "assignField"])
    expect(
      functionBody(normal, name),
      `${name} must harden its nullable value with !!`,
    ).toContain("this.nullableInt()!!");

  // ablation arm
  const genAblate = run([
    "haxe", "tests/haxe/kotlin-coerce-assign/kotlin.hxml",
    "-D", "kotlin_coerce_ablate=Assignment",
    "-D", `kotlin-output=${generatedAblate}`,
  ]);
  expect(genAblate.code, `ablate generation failed: ${genAblate.stderr || genAblate.stdout}`).toBe(0);

  const ablate = await Bun.file(`${generatedAblate}/assigning/AssignCases.kt`).text();
  for (const name of ["assignLocal", "assignArray", "assignField"])
    expect(
      functionBody(ablate, name),
      `${name} must keep its bare nullable value when ablated`,
    ).not.toContain("this.nullableInt()!!");

  // compile arms (GP-ABLATE)
  const kotlinc = Bun.which("kotlinc");
  if (kotlinc === null) {
    process.stderr.write("kotlinc not on PATH: compile stage environment-not-reached");
    return;
  }

  const normalKt = Array.from(new Bun.Glob("**/*.kt").scanSync({ cwd: generated }))
    .map((name) => `${generated}/${name}`);
  const normalCompile = run([kotlinc, ...normalKt, "-d", `${out}/normal.jar`]);
  expect(normalCompile.code, `positive kotlinc must compile`).toBe(0);

  const ablateKt = Array.from(new Bun.Glob("**/*.kt").scanSync({ cwd: generatedAblate }))
    .map((name) => `${generatedAblate}/${name}`);
  const ablateCompile = run([kotlinc, ...ablateKt, "-d", `${out}/ablate.jar`]);
  expect(ablateCompile.code, `ablate kotlinc must reject the bare nullable value`).not.toBe(0);
  expect(ablateCompile.stderr, `ablate stderr must name the type mismatch`).toContain("type mismatch");
}, 180_000);
