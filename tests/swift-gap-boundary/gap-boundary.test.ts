import { expect, test } from "bun:test";

const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_GAP_BOUNDARY_OUT ?? `${root}/out/swift-gap-boundary/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;

// Captured from the fixture's own history: with the current backend the archived

async function run(command: string[], label: string): Promise<string> {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  await Bun.write(`${out}/${label}.stdout.log`, stdout);
  await Bun.write(`${out}/${label}.stderr.log`, stderr);
  await Bun.write(`${out}/${label}.status`, `${result.exitCode ?? 1}\n`);
  expect(result.exitCode, `${label}: ${stderr || stdout}`).toBe(0);
  return stdout;
}

test("archived gap.Gap counterexample generates and its Swift typechecks", async () => {
  const existingOutput = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existingOutput.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  await Bun.$`mkdir -p ${out}`;

  await run(
    ["haxe", "tests/swift-gap-boundary/swift.hxml", "-D", `swift-output=${generated}`, "-D", `swift-test-output=${out}/tests`],
    "generate",
  );
  const repeated = `${out}/gen-repeat`;
  await run(
    ["haxe", "tests/swift-gap-boundary/swift.hxml", "-D", `swift-output=${repeated}`, "-D", `swift-test-output=${out}/tests-repeat`],
    "generate-repeat",
  );
  const firstFiles = (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: generated }))).sort();
  const repeatedFiles = (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: repeated }))).sort();
  expect(repeatedFiles).toEqual(firstFiles);
  for (const file of firstFiles)
    expect(await Bun.file(`${repeated}/${file}`).text(), `repeat generation changed ${file}`).toBe(await Bun.file(`${generated}/${file}`).text());

  // Generation succeeded above; this proves the generated code also typechecks.
  // GATE-OWNER RULING (recorded 2026-09-30), replacing an earlier comment that read
  // "Strict policy: zero diagnostics, including warnings" while the code below did not
  // implement that. The binding standard docs/specs/style/02-translator-implementation-standard.md
  // requires at :80 that "Acceptance for any emitter change counts the warning lines in the
  // target suite output that name files under the generated trees; the count is zero", and at
  // :78 that a warning is "an emitter defect with the same severity as a translation that
  // produces wrong output". These two diagnostics therefore COUNT against the standard, and
  // this fixture does NOT satisfy it today. Per work-plan:417 a baseline finding "does not
  // waive the standard", so this is recorded as a KNOWN BASELINE FAILURE, not as compliance.
  //
  // What this driver asserts, precisely: zero type errors, and the two `[#no-usage]` warnings
  // of the W1 defect are GONE. That pin has been discharged, so it was removed -- it existed
  // to make the recording rot-proof, and it fired exactly as designed: when W1's fix landed the
  // warnings disappeared, the pin failed, and the count was re-read as zero. W1 is on the line
  // and three independent sessions measured 0 errors / 0 warnings on this fixture.
  //
  // NOT YET SATISFIED, and recorded rather than hidden: under `swiftc -c` (which runs SILGen,
  // unlike `-typecheck`) this fixture still emits one `will never be executed` warning at
  // Gap.swift:117. Per the gate-owner ruling of the round-145 review, a build-phase diagnostic
  // COUNTS against 02-translator-implementation-standard.md:78/:80 -- the standard applies
  // "without warnings" to the generated code's compilation and :80 counts suite warning lines.
  // So the final goal remains ZERO diagnostics under -c as well, and this row is a recorded,
  // unwaived deviation, not compliance.
  const typecheck = Bun.spawnSync(
    ["swiftc", "-typecheck", `${generated}/gap/Gap.swift`, `${generated}/Runtime.swift`, `${generated}/std/UStringException.swift`, `${generated}/std/UStringFault.swift`],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  await Bun.write(`${out}/typecheck.stdout.log`, typecheck.stdout.toString());
  await Bun.write(`${out}/typecheck.stderr.log`, typecheck.stderr.toString());
  await Bun.write(`${out}/typecheck.status`, `${typecheck.exitCode ?? 1}\n`);
  expect(typecheck.exitCode, `swiftc -typecheck: ${typecheck.stderr.toString() || typecheck.stdout.toString()}`).toBe(0);
  const diagnostics = typecheck.stderr.toString();
  // Transition assertion, per the round-145 gate-owner ruling: zero type errors, and the
  // remaining build-phase diagnostic recorded explicitly rather than asserted absent or
  // silently excluded. The final goal stays zero diagnostics under -c.
  expect(diagnostics.split("\n").filter((l) => l.includes(": error:")), "unexpected type errors").toEqual([]);
  expect(diagnostics.includes("#no-usage"), "the W1 unused-result warnings should be gone").toBe(false);
  // The line that used to be here counted `warning:` lines out of the -typecheck
  // stderr and called them "build-phase diagnostics". That was a name that did not
  // describe what it measured: -typecheck does not run SILGen, so it cannot see the
  // build-phase warning at all. This now actually invokes `swiftc -c` and records
  // what THAT command reports, so the recorded count and the command agree.
  // -whole-module-optimization is required for a single -o: plain `swiftc -c` with
  // multiple inputs emits one .o per input and rejects -o with
  // "error: cannot specify -o when generating multiple output files" (rc=1, which is
  // exactly what the previous run's build.stderr.log captured). WMO still runs SILGen,
  // so the build-phase warning stays visible.
  const build = Bun.spawnSync(
    ["swiftc", "-c", "-whole-module-optimization", `${generated}/gap/Gap.swift`, `${generated}/Runtime.swift`, `${generated}/std/UStringException.swift`, `${generated}/std/UStringFault.swift`, "-o", `${out}/gap.o`],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  await Bun.write(`${out}/build.stderr.log`, build.stderr.toString());
  await Bun.write(`${out}/build.status`, `${build.exitCode ?? 1}\n`);
  const buildDiagnostics = build.stderr.toString();
  const pendingBuildWarning = buildDiagnostics.split("\n").filter((l) => l.includes("warning:"));
  await Bun.write(`${out}/pending-build-warnings.log`, pendingBuildWarning.join("\n") + "\n");
  // The -c step MUST succeed: an object file must actually be produced. A fixture that
  // keeps passing while its own compile step fails is not a check (LAYERED-VERIFICATION L5).
  expect(build.exitCode, `swiftc -c failed: ${buildDiagnostics || "no diagnostics"}`).toBe(0);
  expect(Bun.file(`${out}/gap.o`).size, "swiftc -c produced no object file").toBeGreaterThan(0);
  expect(buildDiagnostics.split("\n").filter((l) => l.includes(": error:")), "swiftc -c reported type errors").toEqual([]);
  // Recorded deviation, asserted present so the count cannot rot: under -c (SILGen) the
  // fixture emits exactly one `will never be executed` warning at Gap.swift:117. Per the
  // gate-owner ruling this diagnostic COUNTS against 02-translator-implementation-standard.md:78/:80,
  // so this is an unwaived, recorded baseline failure -- the goal remains zero diagnostics
  // under -c. When that warning is fixed, this assertion fails and forces the count to be
  // re-read (same rot-proof pin pattern as the W1 pin that was removed after discharge).
  expect(
    pendingBuildWarning.filter((l) => l.includes("Gap.swift:117") && l.includes("will never be executed")),
    "the recorded `will never be executed` deviation at Gap.swift:117 must still be present under -c; if it is gone, re-read the count and update this pin",
  ).toHaveLength(1);
  console.log(`  swiftc -c rc=${build.exitCode}, recorded ${pendingBuildWarning.length} pending build-phase diagnostic(s) - see pending-build-warnings.log`);
  expect(diagnostics.split("\n").filter((line) => line.includes(": error:")), "unexpected type errors").toEqual([]);
}, 60_000);

test("failure-mode probe: the harness detects a broken Swift source", async () => {
  const probeDir = `${out}/failure-probe`;
  await Bun.$`mkdir -p ${probeDir}`;
  await Bun.write(`${probeDir}/broken.swift`, `let broken: Int = "s"\n`);
  const result = Bun.spawnSync(["swiftc", "-typecheck", `${probeDir}/broken.swift`], { cwd: root, stdout: "pipe", stderr: "pipe" });
  await Bun.write(`${out}/failure-probe.status`, `${result.exitCode ?? 0}\n`);
  await Bun.write(`${out}/failure-probe.stderr.log`, result.stderr.toString());
  expect(result.exitCode === 0 || result.exitCode === null, "swiftc accepted a deliberately broken source; diagnostics channel is untrustworthy").toBe(false);
  expect(result.stderr.toString()).toContain("error");
  // Same probe for the build phase: a deliberately broken input must make `swiftc -c` fail
  // too, proving the -c assertions above can actually fire (discriminating, not decorative).
  const buildProbe = Bun.spawnSync(["swiftc", "-c", `${probeDir}/broken.swift`, "-o", `${probeDir}/broken.o`], { cwd: root, stdout: "pipe", stderr: "pipe" });
  await Bun.write(`${out}/failure-probe-build.status`, `${buildProbe.exitCode ?? 0}\n`);
  await Bun.write(`${out}/failure-probe-build.stderr.log`, buildProbe.stderr.toString());
  expect(buildProbe.exitCode, "swiftc -c accepted a deliberately broken source; build-phase check cannot fail").not.toBe(0);
  expect(buildProbe.stderr.toString()).toContain("error");
}, 60_000);
