import { expect, test } from "bun:test";

// Kotlin cannot smart-cast through a mutable *receiver*: a read of a final
// (val) field through a nullable var property keeps its force extraction on
// the receiver and hardens the final read, even after a null guard proves the
// chain present. This is a two-level chain -- `o.current` (var, nullable)
// then `.fin` (final, nullable) -- which the single-level
// kotlin-var-field-smartcast fixture deliberately does not cover: that
// fixture pins a direct property read (holder.value), not a chained one.
//
// Dev-time commits 40820371/57b1beb8 introduced this probe for the Kotlin
// mutable-chain fix; until this test existed the directory was collected by
// nothing (fixture-reachability's original 35 -> 36 step). Wiring it in makes
// that loss impossible to repeat. (MutableChainProbe)
const root = `${import.meta.dir}/../../..`;
const out = Bun.env.BORING_MUTABLECHAIN_OUT ?? `${root}/out/kotlin-mutable-chain-probe/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;

async function run(command: Array<string>, label: string): Promise<string> {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  await Bun.write(`${out}/${label}.stdout.log`, stdout);
  await Bun.write(`${out}/${label}.stderr.log`, stderr);
  await Bun.write(`${out}/${label}.status`, `${result.exitCode ?? 1}\
`);
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

test("a final field read through a nullable var receiver keeps its force extraction and hardens", async () => {
  const existing = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existing.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  await Bun.$`mkdir -p ${out}`;

  await run(
    ["haxe", "tests/haxe/kotlin-mutable-chain-probe/kotlin-gen.hxml", "-D", `kotlin-output=${generated}`],
    "generate",
  );

  const source = await Bun.file(`${generated}/chk/Ops.kt`).text();
  const body = functionBody(source, "viaVarOuter");

  // The measured subject: the var receiver `o.current` must keep its force
  // extraction on every read of the chained final field, guard included.
  expect(/o\.current!!\.fin/.test(body), `var-receiver read must extract:\n${body}`).toBe(true);
  // The chained final read feeding want() must harden (elvis throw), not
  // degrade into a safe call that would change the argument's type.
  expect(/fin \?: throw/.test(body), `chained read must harden:\n${body}`).toBe(true);
  expect(/\?\./.test(body), `chained read must not safe-call:\n${body}`).toBe(false);

  // The emitted Kotlin must actually compile under the real compiler. A
  // missing kotlinc is recorded as environment-not-reached (the convention
  // tests/haxe/dc-promoted-eval/run.sh states), never silently skipped.
  const kotlinc = Bun.which("kotlinc");
  if (kotlinc === null) {
    process.stderr.write("kotlinc not on PATH: compile stage environment-not-reached\n");
    return;
  }
  const files = Array.from(new Bun.Glob("chk/*.kt").scanSync({ cwd: generated }))
    .map((name) => `${generated}/${name}`);
  await run([kotlinc, ...files, "-d", `${out}/classes`], "kotlinc");
}, 180_000);
