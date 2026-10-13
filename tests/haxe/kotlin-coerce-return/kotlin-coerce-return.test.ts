import { expect, test } from "bun:test";

// Kotlin Return coercion (P2.7): a returned value that must satisfy a
// non-null return-type contract is hardened with !!. The destination
// admitsAbsence follows the current function/lambda return type (the P1
// rebound type), so inside a Null<String>-returning lambda the return stays
// bare while the enclosing non-null String return extracts with !! (contract 1):
//
//   * inside the lambda "fun(): String?" the body emits a bare
//     "return _gthis.nullableString()" (the lambda's own nullable return
//     type admits absence),
//   * the outer "fun lambdaReturn(): String" emits "return f()!!".
//
// The positive tree compiles. The ablation arm (-D kotlin_coerce_ablate=Return)
// drops the outer !!, leaving "return f()" so kotlinc rejects it with a type
// mismatch (GP-ABLATE). Assertions name the emitted forms, not merely "it
// compiles" (LAYERED-VERIFICATION).
const root = `${import.meta.dir}/../../..`;
const out =
  Bun.env.BORING_COERCE_RETURN_OUT ??
  `${root}/out/kotlin-coerce-return/test-${crypto.randomUUID()}`;
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

test("a nullable value returned through a Null<String> lambda stays bare while the outer String return extracts", async () => {
  await Bun.$`mkdir -p ${out}`;

  // positive arm
  const gen = run([
    "haxe", "tests/haxe/kotlin-coerce-return/kotlin.hxml",
    "-D", `kotlin-output=${generated}`,
  ]);
  expect(gen.code, `haxe generation failed: ${gen.stderr || gen.stdout}`).toBe(0);

  const files = Array.from(new Bun.Glob("**/*.kt").scanSync({ cwd: generated })).sort();
  expect(files.length).toBeGreaterThan(0);

  const normal = await Bun.file(`${generated}/returning/ReturnCases.kt`).text();
  const body = functionBody(normal, "lambdaReturn");
  // contract 1: conversion inside the lambda uses the lambda's own nullable
  // return type, so the body stays bare ...
  expect(body, "lambda body must keep its bare nullable return").toContain("return _gthis.nullableString()");
  expect(body, "lambda body must NOT harden with !!").not.toContain("_gthis.nullableString()!!");
  // ... while the outer non-null String return extracts with !!.
  expect(body, "outer return must harden the nullable call with !!").toContain("return f()!!");

  // ablation arm
  const genAblate = run([
    "haxe", "tests/haxe/kotlin-coerce-return/kotlin.hxml",
    "-D", "kotlin_coerce_ablate=Return",
    "-D", `kotlin-output=${generatedAblate}`,
  ]);
  expect(genAblate.code, `ablate generation failed: ${genAblate.stderr || genAblate.stdout}`).toBe(0);

  const ablate = await Bun.file(`${generatedAblate}/returning/ReturnCases.kt`).text();
  expect(functionBody(ablate, "lambdaReturn"), "ablate must drop the outer !!").not.toContain("return f()!!");

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
  expect(ablateCompile.code, `ablate kotlinc must reject the bare nullable return`).not.toBe(0);
  expect(ablateCompile.stderr, `ablate stderr must name the type mismatch`).toContain("type mismatch");
}, 180_000);
