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
    "branch-true=1:1",
    "branch-false=2:1",
    "coalesced-null=0:empty",
    "coalesced-present=1:present",
    "default-omitted=0:empty",
    "default-null=0:empty",
    "default-present=1:present",
    "nullable-fallback-omitted=nil",
    "nullable-fallback-null=nil",
    "nullable-fallback-present=present:1",
    "guarded-nullable-fallback=present:1",
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
  const sources = [
    `${generated}/Runtime.swift`,
    `${generated}/Test.swift`,
    `${generated}/std/UStringException.swift`,
    `${generated}/std/UStringFault.swift`,
    `${generated}/boring/ReadOnlyBoundaryOps.swift`,
    `${import.meta.dir}/ReadOnlyBoundaryRuntimeTests.swift`,
  ];
  await run(["swiftc", "-o", `${out}/ReadOnlyBoundaryRuntimeTests`, ...sources], "swiftc");
  const swift = await run([`${out}/ReadOnlyBoundaryRuntimeTests`], "swift-runtime");
  expect(swift.trim().split("\n")).toEqual(expected);
  const compilerDiagnostics = await Bun.file(`${out}/swiftc.stderr.log`).text();
  expect(compilerDiagnostics.trim(), "generated Swift compiler diagnostics").toBe("");
}, 60_000);
