import { afterEach, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const entry = resolve("out/driver/driver.js");
const dirs: string[] = [];
type Fixture = { dir: string; file: string };
type RunResult = { code: number; output: string };

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function fixture(config: Record<string, unknown>): Fixture {
  const dir = mkdtempSync(join(tmpdir(), "boring-driver-"));
  dirs.push(dir);
  const file = join(dir, "boring.json");
  writeFileSync(file, JSON.stringify({ outRoot: "out", resultsDir: "results", baseline: "reference", sourceRoots: [], bundles: [
    { id: "reference", target: "ts" },
    { id: "header", target: "ts", test: false },
  ], ...config }));
  return { dir, file };
}

function run(file: string, args: string[], env: Record<string, string> = {}): RunResult {
  const result = Bun.spawnSync([process.execPath, entry, ...args, "--project", file], {
    cwd: resolve("."), env: { ...process.env, ...env }, stdout: "pipe", stderr: "pipe",
  });
  return { code: result.exitCode, output: result.stdout.toString() + result.stderr.toString() };
}

test("compare ignores configurations without tests and runs outside the boring checkout", () => {
  const { dir, file } = fixture({});
  mkdirSync(join(dir, "results"));
  writeFileSync(join(dir, "results", "reference.jsonl"), '{"id":"same","name":"same","verdict":"pass"}\n');
  const result = run(file, ["compare"]);
  expect(result.code).toBe(0);
  expect(result.output).toContain("All 1 targets (reference)");
  expect(result.output).not.toContain("header.jsonl");
});

test("compare reports a verdict mismatch", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" }, { id: "other", target: "ts" },
  ] });
  mkdirSync(join(dir, "results"));
  writeFileSync(join(dir, "results", "reference.jsonl"), '{"id":"same","name":"same","verdict":"pass"}\n');
  writeFileSync(join(dir, "results", "other.jsonl"), '{"id":"same","name":"same","verdict":"fail"}\n');
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain("Verdict mismatch on same");
});

test("compare excludes a tested configuration marked compare=false", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" }, { id: "alternate", target: "ts", compare: false },
  ] });
  mkdirSync(join(dir, "results"));
  writeFileSync(join(dir, "results", "reference.jsonl"), '{"id":"same","name":"same","verdict":"pass"}\n');
  const result = run(file, ["compare"]);
  expect(result.code).toBe(0);
  expect(result.output).toContain("All 1 targets (reference)");
  expect(result.output).not.toContain("alternate.jsonl");
});

test("baseline must participate in compare", () => {
  const { file } = fixture({ bundles: [{ id: "reference", target: "ts", compare: false }] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('baseline "reference" must participate in compare');
});

test("a configuration cannot compare results without tests", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts" }, { id: "header", target: "ts", test: false, compare: true },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "header": compare=true requires test=true');
});

test("explicit test rejects a configuration marked test=false", () => {
  const { file } = fixture({});
  const result = run(file, ["test", "header"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain("test=false");
});

test("baseline must have tests", () => {
  const { file } = fixture({ baseline: "header" });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('baseline "header" must have tests');
});

test("gen runs afterGen with the project as working directory", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts", afterGen: { command: process.execPath, args: ["write-marker.ts"] } },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  writeFileSync(fakeHaxe, "#!/bin/sh\nexit 0\n");
  chmodSync(fakeHaxe, 0o755);
  writeFileSync(join(dir, "write-marker.ts"), 'await Bun.write("marker.txt", "generated");\n');
  const result = run(file, ["gen", "reference"], { PATH: bin + ":" + process.env.PATH });
  expect(result.code).toBe(0);
  expect(readFileSync(join(dir, "marker.txt"), "utf8")).toBe("generated");
});

test("verify with pack ignores configurations without package metadata", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" },
    { id: "header", target: "ts", test: false },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  const generated = `import { test } from "bun:test";
import { appendFileSync } from "node:fs";
test("same", () => appendFileSync(process.env.BORING_TEST_RESULTS!,
  JSON.stringify({ id: "same", name: "same", verdict: "pass" }) + "\\n"));
`;
  writeFileSync(fakeHaxe, `#!/usr/bin/env bun
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
const output = args.find((arg) => arg.startsWith("ts-test-output="))?.slice("ts-test-output=".length);
if (output) {
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, "driver.test.ts"), ${JSON.stringify(generated)});
}
`);
  chmodSync(fakeHaxe, 0o755);
  const result = run(file, ["verify", "--with-pack"], { PATH: bin + ":" + process.env.PATH });
  expect(result.code).toBe(0);
  expect(result.output).toContain("All 1 targets (reference)");
  expect(result.output).not.toContain("[pack]");
});

test("run.env cannot replace the driver's results file", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", run: { env: { BORING_TEST_RESULTS: "wrong.jsonl" } } },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "reference": run.env may not set BORING_TEST_RESULTS');
});

test("pack passes the declared license to the compiler", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts", package: { name: "demo", version: "1.0.0", license: "MPL-2.0" } },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "haxe"), '#!/bin/sh\nprintf "%s\\n" "$@" > "$BORING_ARG_LOG"\n');
  writeFileSync(join(bin, "tsc"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "haxe"), 0o755);
  chmodSync(join(bin, "tsc"), 0o755);
  const argLog = join(dir, "haxe-args.txt");
  const result = run(file, ["pack", "reference"], { PATH: bin + ":" + process.env.PATH, BORING_ARG_LOG: argLog });
  expect(result.code).toBe(0);
  expect(readFileSync(argLog, "utf8").split("\n")).toContain("package-license=MPL-2.0");
});

test("package license must be a nonempty string when declared", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", package: { name: "demo", version: "1.0.0", license: "" } },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "reference": package license must not be empty');
});
