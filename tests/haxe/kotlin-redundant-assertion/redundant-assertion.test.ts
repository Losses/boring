import { expect, test } from "bun:test";

/**
 * Redundant-assertion coverage on an immutable nullable local.
 *
 * `runtime.StringTools.isSpace` reads one `final` nullable local three times
 * inside a single boolean expression. `charCodeAt` lowers to
 * `run { ... else null }`, so the local's Kotlin storage is `Int?`.
 *
 * The first read must assert, because nothing has proven the value present.
 * Kotlin's not-null assertion then holds the value non-null for the region the
 * assertion dominates, and the local is a `val` that is never reassigned, so
 * Kotlin's smart cast is in effect at every later read in that region: a second
 * assertion there can never throw. Measured (kotlinc 2.4.10) on
 * `c!! > 8 && c!! < 14`: `warning: unnecessary non-null assertion (!!) on a
 * non-null receiver of type 'Int'` at the second `!!`. The second `!!` is
 * therefore redundant, and
 * `docs/specs/style/02-translator-implementation-standard.md:78/:80` counts a
 * warning naming a file under the generated trees as an emitter defect with the
 * same severity as wrong output.
 *
 * The third read, `c == 32`, is correct for a different reason: Kotlin equality
 * is null-safe and the emitter never asserts an `OpEq`/`OpNotEq` operand. That
 * is why the third read looks "covered" while the second does not -- the proof
 * mechanism did not reach either of them. `eqRead` isolates that rule.
 *
 * This fixture records the measured emission. The duplicate-assertion counts
 * below are RECORDED MEASUREMENTS. They state no requirement: the emitter fix for this
 * finding is a separate task (the audit task is
 * `audit/kotlin-redundant-assertion-vs-master`, board row
 * `t-mupmsxcx-qjsj`). When that fix is made, these constants must be lowered
 * deliberately, together with
 * `docs/architecture/evidence/kotlin-redundant-assertion/REPORT.md`. The
 * fixture exists so the shape cannot change while nobody is looking -- the
 * same recording rule that `tests/fixture-reachability.test.ts` states for its
 * own constant.
 *
 * The permanent assertions in this file are the ones that stay true after the
 * fix: the first read keeps its assertion, the equality read never takes one,
 * and both sibling ternary arms keep theirs.
 */
const root = `${import.meta.dir}/../../..`;
const out = Bun.env.BORING_REDUNDANT_ASSERTION_OUT ?? `${root}/out/kotlin-redundant-assertion/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;

/** Recorded on 2026-10-01 at revision e54611c1 (mainline tip). LOWER IT when the emitter fix is made. */
const RECORDED_DUPLICATE_ASSERTIONS: Record<string, number> = {
  isSpace: 2,
  lowerBound: 2,
  threeReads: 2,
};

/** Recorded on 2026-10-01 at revision e54611c1 (kotlinc 2.4.10, JRE 21). */
const RECORDED_KOTLINC_REDUNDANT_WARNINGS = 3;

async function run(command: Array<string>, label: string): Promise<{ stdout: string; stderr: string }> {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  await Bun.write(`${out}/${label}.stdout.log`, stdout);
  await Bun.write(`${out}/${label}.stderr.log`, stderr);
  await Bun.write(`${out}/${label}.status`, `${result.exitCode ?? 1}\n`);
  expect(result.exitCode, `${label}: ${stderr || stdout}`).toBe(0);
  return { stdout, stderr };
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

function assertions(body: string): number {
  return (body.match(/!!/g) ?? []).length;
}

test("a nullable local read after its own printed assertion takes no second assertion", async () => {
  const existing = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existing.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  await Bun.$`mkdir -p ${out}`;

  await run(
    ["haxe", "tests/haxe/kotlin-redundant-assertion/kotlin-gen.hxml", "-D", `kotlin-output=${generated}`],
    "generate",
  );

  const file = `${generated}/redundantassertion/RedundantAssertionOps.kt`;
  const source = await Bun.file(file).text();

  const spaceBody = functionBody(source, "isSpace");
  // Permanent: the first read has nothing proving the value present, so it
  // must assert -- dropping this one would not compile.
  expect(/c!! > 8/.test(spaceBody), `first read must assert:\n${spaceBody}`).toBe(true);
  // Permanent: equality never asserts, whatever the proof state. This is why
  // the third read of the runtime `isSpace` is correct without the proof
  // mechanism having reached it.
  const eqBody = functionBody(source, "eqRead");
  expect(assertions(eqBody), `an equality read must not assert:\n${eqBody}`).toBe(0);
  // Permanent: sibling arms do not dominate each other, so a suppression that
  // ignored arm scope would drop the second one and kotlinc would reject the
  // result. Any fix for the finding above must keep this true.
  const armBody = functionBody(source, "armRead");
  expect(assertions(armBody), `both sibling arms must assert:\n${armBody}`).toBe(2);

  // Permanent: the emitter's own "an assertion was already printed for this
  // stable subject" record is consulted by the member-access read site, so the
  // second read of `x` drops its assertion. That is the contrast control for
  // the finding: the fact is in hand one read site away, so the duplicate
  // assertion on a bare local operand is a missing consultation there, and no
  // proof the emitter is unable to make.
  const memberSource = await Bun.file(`${generated}/redundantassertion/MemberRegistryProbe.kt`).text();
  const memberBody = functionBody(memberSource, "localMember");
  expect(/x!!\.flag/.test(memberBody), `first member read must assert the receiver:\n${memberBody}`).toBe(true);
  expect(/a && x\.flag/.test(memberBody), `second member read must drop the repeated receiver assertion:\n${memberBody}`).toBe(true);

  // Recorded: the duplicate assertion the finding is about. `threeReads`
  // shows it is not limited to sibling operands of one operator -- the second
  // read is a separate statement, still dominated by the first assertion.
  for (const [name, recorded] of Object.entries(RECORDED_DUPLICATE_ASSERTIONS)) {
    const body = functionBody(source, name);
    const measured = assertions(body);
    expect(
      measured,
      `${name} emitted ${measured} assertions, recorded measurement is ${recorded}.\n`
        + `If the duplicate assertion is gone, the emitter fix landed: lower\n`
        + `RECORDED_DUPLICATE_ASSERTIONS and REPORT.md together.\n${body}`,
    ).toBe(recorded);
  }
  // The measured line itself, so the report's quotation is pinned by the suite.
  expect(source).toContain("return c!! > 8 && c!! < 14 || c == 32");

  // The emitted Kotlin must actually reach the real compiler. A missing
  // kotlinc is recorded as environment-not-reached, the convention
  // tests/haxe/dc-promoted-eval/run.sh states, never a silent pass.
  const kotlinc = Bun.which("kotlinc");
  if (kotlinc === null) {
    process.stderr.write("kotlinc not on PATH: compile stage environment-not-reached\n");
    return;
  }
  // kotlinc reports diagnostics on stderr; the step keeps its exit code at 0
  // (a warning is not a compile failure), which is exactly why the standard
  // counts warning lines and refuses to trust the exit code alone.
  const { stderr: diagnostics } = await run([kotlinc, file, "-d", `${out}/classes`], "kotlinc");
  const redundantLines = diagnostics.split("\n").filter((line) => line.includes("unnecessary non-null assertion"));
  expect(
    redundantLines.length,
    `kotlinc reported ${redundantLines.length} redundant-assertion warnings, recorded measurement is `
      + `${RECORDED_KOTLINC_REDUNDANT_WARNINGS}. If this dropped to 0, the emitter fix landed: lower the\n`
      + `constant and REPORT.md together.\n${diagnostics}`,
  ).toBe(RECORDED_KOTLINC_REDUNDANT_WARNINGS);
}, 180_000);
