import { expect, test } from "bun:test";

// Collected regression for the same-type-parameter dedup in
// packages/compiler/SourceComparisonAnalysis.hx. Two nested Pair<T> fields of
// one Boxed<T> must share ONE nested record node: a macro `Ref` wrapper is
// freshly allocated on every access, so pointer equality cannot decide the
// parameter identity. Commit e6fad00b fixed that by comparing the
// owner-qualified parameterIdentity serial key, but the fixture shipped with
// the fix and no collected test, so the reachability guard counted it as
// unwatched (fixture-reachability 35 vs recorded 34).
//
// The probe runs from a global @:build while revp9.Trigger compiles and prints
// the DEDUP / LIMITED / CONTROL readings that run.sh already checks; the same
// readings are asserted here. (DcSameTypeParameter)
const root = `${import.meta.dir}/../../..`;
const out = `${root}/out/dc-same-type-parameter/test-${crypto.randomUUID()}`;

test("one Boxed<T> parameter dedups its nested Pair<T> nodes at the default and reduced budget", async () => {
  await Bun.$`mkdir -p ${out}`;

  const haxe = Bun.which("haxe");
  if (haxe === null) {
    // Same convention as tests/haxe/dc-promoted-eval/run.sh: an absent
    // toolchain is recorded as environment-not-reached, never a silent pass.
    process.stderr.write("haxe not on PATH: probe stage environment-not-reached\n");
    return;
  }

  const result = Bun.spawnSync(
    [haxe, "tests/haxe/dc-same-type-parameter/build.hxml"],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  await Bun.write(`${out}/probe.stdout.log`, stdout);
  await Bun.write(`${out}/probe.stderr.log`, stderr);

  expect(result.exitCode, `probe failed: ${stderr || stdout}`).toBe(0);

  // The measured subject: the child and pair nodes are one node, and both keep
  // the complete field shape under the default budget.
  expect(stdout, `dedup must hold:\n${stdout}`).toContain("DEDUP ok:true");
  expect(stdout, `child node must be Complete:\n${stdout}`).toContain("DEDUP child state:Complete");
  expect(stdout, `pair node must be Complete:\n${stdout}`).toContain("DEDUP pair state:Complete");
  // The reduced budget must prune without collapsing the nested nodes.
  expect(stdout, `reduced budget must keep nested nodes Complete:\n${stdout}`).toContain(
    "LIMITED allNestedComplete:true sawNested:true",
  );
  // The control: a concrete Int pair dedups on the same measure, so a blanket
  // "never dedup" regression fails here as well.
  expect(stdout, `concrete control must dedup:\n${stdout}`).toContain("CONTROL concrete dedup:true");
}, 180_000);
