import { expect, test } from "bun:test";

// Kotlin does not smart-cast a mutable property, so a read through a nullable
// `var` must keep its force extraction even when a null guard proves the value
// present; a `final` (val) property may smart-cast.
//
// Commit 8214566d ("fix(kotlin): keep force extraction on var-property
// null-narrowing") added that distinction on the
// ci/collected-suite-failure-attribution lineage (it is not on the
// arch/agent-guided-governance base), and no test in either tree pinned
// it -- which is how a merge silently dropped it and left the emitted Kotlin
// failing kotlinc. This test exists to make that loss impossible to repeat.
// (VarFieldSmartCast)
const root = `${import.meta.dir}/../../..`;
const out = Bun.env.BORING_VARFIELD_OUT ?? `${root}/out/kotlin-var-field-smartcast/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;

async function run(command: Array<string>, label: string): Promise<string> {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  await Bun.write(`${out}/${label}.stdout.log`, stdout);
  await Bun.write(`${out}/${label}.stderr.log`, stderr);
  await Bun.write(`${out}/${label}.status`, `${result.exitCode ?? 1}\n`);
  expect(result.exitCode, `${label}: ${stderr || stdout}`).toBe(0);
  return stdout;
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

test("a nullable var property read keeps its force extraction; a val property smart-casts", async () => {
  const existing = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existing.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  await Bun.$`mkdir -p ${out}`;

  await run(
    ["haxe", "tests/haxe/kotlin-var-field-smartcast/kotlin-gen.hxml", "-D", `kotlin-output=${generated}`],
    "generate",
  );

  const source = await Bun.file(`${generated}/varfieldsmartcast/VarFieldSmartCastOps.kt`).text();
  const varBody = functionBody(source, "readThroughVar");
  const valBody = functionBody(source, "readThroughVal");

  // The measured subject: a mutable property that Kotlin will not smart-cast.
  expect(/holder\.value!!\./.test(varBody), `var read must extract:\n${varBody}`).toBe(true);
  // The control: the same shape as a final property may smart-cast. If this
  // ever extracts too, the distinction has been flattened rather than kept.
  expect(/holder\.value\./.test(valBody) && !/holder\.value!!\./.test(valBody), `val read must smart-cast:\n${valBody}`).toBe(true);
  // Neither may degrade into a safe call, which would change the value's type.
  expect(/\?\./.test(varBody), `var read must not safe-call:\n${varBody}`).toBe(false);
  expect(/\?\./.test(valBody), `val read must not safe-call:\n${valBody}`).toBe(false);

  // The emitted Kotlin must actually compile under the real compiler. A
  // missing kotlinc is recorded as environment-not-reached, the convention
  // tests/haxe/dc-promoted-eval/run.sh states ("recorded as
  // environment-not-reached and never silently skipped"), rather than
  // returning quietly -- a silent skip would make the number of assertions
  // depend on the machine and would let the strongest check here not run.
  const kotlinc = Bun.which("kotlinc");
  if (kotlinc === null) {
    process.stderr.write("kotlinc not on PATH: compile stage environment-not-reached\n");
    return;
  }
  const files = Array.from(new Bun.Glob("varfieldsmartcast/*.kt").scanSync({ cwd: generated }))
    .map((name) => `${generated}/${name}`);
  await run([kotlinc, ...files, "-d", `${out}/classes`], "kotlinc");
}, 180_000);
