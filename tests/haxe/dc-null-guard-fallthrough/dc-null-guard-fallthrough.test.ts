import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

// Collected regression for the Dart emitter's fall-through null-guard
// promotion. Before the fix, `if (s == null) { ... }` with a non-exiting
// then-arm promoted `s` past the guard unconditionally, so the required
// non-null assertion was suppressed and the emitted Dart failed
// `dart analyze` (unchecked_use_of_nullable_value) and `dart compile`.
//
// This drives the fixture's own runner (run.sh), which generates Dart, runs
// `dart analyze --fatal-infos`, compiles, runs and compares against
// expected.txt, and records every stage's exit status. The runner is invoked
// with DC_DART_FIX2_SKIP_VCS=1 so the collected suite never shells out to
// native git (the board owns version control). (NullGuardFallthroughCollect)
const root = `${import.meta.dir}/../../..`;

function statusOf(attempt: string, name: string): number | null {
  try {
    return Number.parseInt(readFileSync(`${attempt}/stages/${name}/status`, "utf8").trim(), 10);
  } catch {
    return null;
  }
}

test("fall-through if (x == null) guard keeps the required ! (p2); terminating guard stays bare (p7)", async () => {
  const haxe = Bun.which("haxe");
  const dart = Bun.which("dart");
  if (haxe === null || dart === null) {
    process.stderr.write(`haxe=${haxe} dart=${dart}: toolchain environment-not-reached\n`);
    return;
  }

  const out = `${root}/out/dc-null-guard-fallthrough/test-${crypto.randomUUID()}`;
  const attemptName = `attempt-${crypto.randomUUID()}`;
  const attempt = `${out}/${attemptName}`;
  const runner = Bun.spawnSync(["bash", `${import.meta.dir}/run.sh`], {
    cwd: root,
    env: {
      ...process.env,
      DC_DART_FIX2_SKIP_VCS: "1",
      DC_DART_FIX2_EVIDENCE: out,
      DC_DART_FIX2_ATTEMPT: attemptName,
      IN_NIX_SHELL: process.env.IN_NIX_SHELL ?? "1",
    },
    stdout: "pipe",
    stderr: "pipe",
  });

  if (statusOf(attempt, "gen-dart") !== 0) {
    throw new Error(
      `gen-dart failed (rc=${statusOf(attempt, "gen-dart")}):\n${runner.stdout.toString()}\n${runner.stderr.toString()}`,
    );
  }

  const generated = readFileSync(`${attempt}/generated-dart-probe.dart`, "utf8");
  const p2 = generated.slice(generated.indexOf("int p2FallThrough"), generated.indexOf("int p7TerminatingGuard"));
  const p7 = generated.slice(generated.indexOf("int p7TerminatingGuard"), generated.indexOf("int p8GuardThenReassign"));

  // The discriminator: the guard body falls through, so the local may still be
  // null and the read must carry the non-null assertion.
  expect(p2, `p2 must assert non-null:\n${p2}`).toContain("return s!.length;");
  // The positive control: the guard body exits, so the bare read is correct and
  // must not gain a redundant assertion.
  expect(p7, `p7 must stay bare:\n${p7}`).toContain("return t.length;");
  expect(p7, `p7 must not gain a redundant assertion:\n${p7}`).not.toContain("t!.length");

  // The analyzer must report no errors. The fixture intentionally keeps one
  // unused local, so --fatal-infos makes the run non-zero; only real
  // diagnostics are rejected here.
  const analyzeOut = readFileSync(`${attempt}/stages/dart-analyze/stdout`, "utf8");
  expect(analyzeOut, `analyzer errors:\n${analyzeOut}`).not.toContain("error -");

  // p8-p11 readings must match the fixture's expected join facts, which
  // requires the generated program to compile and run.
  expect(statusOf(attempt, "dart-compile"), "dart compile").toBe(0);
  expect(statusOf(attempt, "dart-run"), "dart run").toBe(0);
  expect(statusOf(attempt, "dart-compare"), "dart compare").toBe(0);
  expect(readFileSync(`${attempt}/stages/dart-run/stdout`, "utf8")).toBe(
    readFileSync(`${import.meta.dir}/expected.txt`, "utf8"),
  );

  // The Kotlin contrast is the join-fact oracle this fixture compares against.
  expect(statusOf(attempt, "gen-kotlin"), "gen-kotlin").toBe(0);
}, 300_000);
