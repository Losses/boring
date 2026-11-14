import { expect, test } from "bun:test";

const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_READONLY_BOUNDARY_OUT ?? `${root}/out/readonly-boundary/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;

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

test("Swift read-only array boundary shares storage and preserves flow", async () => {
  const existingOutput = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existingOutput.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  await Bun.$`mkdir -p ${out}`;
  const oracle = await run(["haxe", "tests/swift-readonly-boundary/oracle.hxml"], "oracle");
  const expected = [
    "alias=7:2",
    "effect=1:8:1",
    "reference=11:true:17:true",
    "nullable-elements=3:5:3",
    "nullable-literal-elements=2:5:3",
    "nullable-local-literal-elements=2:5:3",
    "present-optional=6:1",
    "absent-optional=nil",
    "guarded-present=4:1",
    "guarded-absent=nil",
    "guarded-field=8:1",
    "null-reassigned=21:2:2109",
    "cleared=nil",
    "direct-call=2:4:AB",
    "constructor=6:1",
    "field-assignment=14:1",
    "static-field=41:1",
    "return=13:2",
    "enum=5:1",
    "branch-true=1:1:present",
    "branch-false=1:2:present",
    "coalesced-null=0:empty",
    "coalesced-present=1:9:present",
    "default-omitted=0:empty",
    "default-null=0:empty",
    "default-present=1:present",
    "nullable-fallback-omitted=nil",
    "nullable-fallback-null=nil",
    "nullable-fallback-present=present:1",
    "guarded-nullable-fallback=present:1",
    "traverse-readonly=3:12",
  ];
  expect(oracle.split("\n").map((line) => line.replace(/^.*?:\d+: /, "")).filter(Boolean)).toEqual(expected);

  await run(
    ["haxe", "tests/swift-readonly-boundary/swift.hxml", "-D", `swift-output=${generated}`, "-D", `swift-test-output=${out}/tests`],
    "generate",
  );
  const repeated = `${out}/gen-repeat`;
  await run(
    ["haxe", "tests/swift-readonly-boundary/swift.hxml", "-D", `swift-output=${repeated}`, "-D", `swift-test-output=${out}/tests-repeat`],
    "generate-repeat",
  );
  const firstFiles = (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: generated }))).sort();
  const repeatedFiles = (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: repeated }))).sort();
  expect(repeatedFiles).toEqual(firstFiles);
  for (const file of firstFiles)
    expect(await Bun.file(`${repeated}/${file}`).text(), `repeat generation changed ${file}`).toBe(await Bun.file(`${generated}/${file}`).text());
  // PIT-255: the read-only-to-mutable boundary must render toMutableArray()
  // exactly once; an extra TiqianArray(...) wrapper is the defect that made
  // VectorCodec.swift:49:43 fail to compile.
  const opsSource = await Bun.file(`${generated}/boring/ReadOnlyBoundaryOps.swift`).text();
  expect(opsSource).toContain("for value in values.toMutableArray() {");
  expect(opsSource, "read-only-to-mutable boundary re-wrapped TiqianArray").not.toContain("TiqianArray(values.toMutableArray())");
  const sources = [
    `${generated}/Runtime.swift`,
    `${generated}/Test.swift`,
    `${generated}/std/UStringException.swift`,
    `${generated}/std/UStringFault.swift`,
    `${generated}/boring/ReadOnlyBoundaryOps.swift`,
    `${import.meta.dir}/ReadOnlyBoundaryRuntimeTests.swift`,
  ];
  // The nix swiftc FHS wrapper records a generic /lib64 interpreter while
  // the executable RUNPATH resolves libc to the devShell glibc, so a host
  // with an older system loader (ubuntu-24.04 runners carry 2.39) drives the
  // newer libc and the process aborts after startup ("*** stack smashing
  // detected ***: terminated", exitCode null). Package.swift and the other
  // ad-hoc swiftc binaries in this repository pin the interpreter through
  // BORING_SWIFT_DYNAMIC_LINKER; this invocation pins it the same way.
  const pinnedLoader = Bun.env.BORING_SWIFT_DYNAMIC_LINKER;
  const loader = pinnedLoader == null ? [] : ["-Xlinker", "-dynamic-linker", "-Xlinker", pinnedLoader];
  await run(["swiftc", ...loader, "-o", `${out}/ReadOnlyBoundaryRuntimeTests`, ...sources], "swiftc");
  // The pinned loader skips the host's default library directories, and
  // libstdc++ is a transitive dependency of the swift libraries, so the run
  // hands the runtime the devShell's library path (the same
  // BORING_SWIFT_LIBDISPATCH prefix package.json uses for the SwiftPM test
  // binaries). A host without the pin keeps its own loader and library path.
  const swift = await run(pinnedLoader == null
    ? [`${out}/ReadOnlyBoundaryRuntimeTests`]
    : ["env", `LD_LIBRARY_PATH=${Bun.env.BORING_SWIFT_LIBDISPATCH ?? ""}`, `${out}/ReadOnlyBoundaryRuntimeTests`], "swift-runtime");
  expect(swift.trim().split("\n")).toEqual(expected);
  const compilerDiagnostics = await Bun.file(`${out}/swiftc.stderr.log`).text();
  expect(compilerDiagnostics.trim(), "generated Swift compiler diagnostics").toBe("");
  // Three haxe runs plus the swiftc compile and binary run measured at
  // 79.9 s total (baseline machine, quiet window; Bun.spawnSync blocks the
  // timer, so the budget must cover the whole body); 180_000 keeps ≥2×
  // margin. The explicit timeout raises only the harness patience for those
  // subprocesses, never the asserted behavior.
}, 180_000);
