import { expect, test } from "bun:test";

// The generation half of block B. The positive case pins the ownership shapes
// and scans the generated tree for the unavailable release family; the two
// negative cases prove the generation-time rules actually fire.

const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_SWIFT_OWNERSHIP_OUT ?? `${root}/out/swift-ownership-check/test-${crypto.randomUUID()}`;

function run(command: string[]): { stdout: string; stderr: string; code: number | null } {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  return { stdout: result.stdout.toString(), stderr: result.stderr.toString(), code: result.exitCode };
}

test("B1 generates ARC-visible CF values and never the release family", async () => {
  const existing = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existing.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  Bun.spawnSync(["mkdir", "-p", out]);

  const generate = run([
    "haxe", "tests/swift-ownership-check/check.hxml",
    "-D", `swift-output=${out}/gen`,
    "-D", `swift-test-output=${out}/tests`,
  ]);
  expect(generate.code, generate.stderr || generate.stdout).toBe(0);

  const sources = (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: `${out}/gen` }))).sort();
  expect(sources.length).toBeGreaterThan(0);
  const all = (await Promise.all(sources.map((path) => Bun.file(`${out}/gen/${path}`).text()))).join("\n");
  for (const banned of ["CFRelease", "CFRetain", "CGContextRelease", "CGColorSpaceRelease", "CGPathRelease"])
    expect(all, `generated tree must not call ${banned}`).not.toContain(banned);

  const fixture = await Bun.file(`${out}/gen/own/OwnershipFixture.swift`).text();
  expect(fixture).toContain("var fonts = [Int32: CTFont]()");
  expect(fixture).toContain("var lines = [Int32: CTLine]()");
  expect(fixture).toContain("Unmanaged.passUnretained(");
  expect(fixture).toContain("Unmanaged<CTRun>.fromOpaque(");
  expect(fixture).toContain("Unmanaged<CFString>.fromOpaque(");
  expect(fixture).toContain("var cache = [Int32: CTLine]()");
});

test("B1 rejects a declared CFRelease at generation time", () => {
  const result = run([
    "haxe", "tests/swift-ownership-check/check-release-negative.hxml",
    "-D", `swift-output=${out}/release-negative`,
    "-D", `swift-test-output=${out}/release-negative-tests`,
  ]);
  const text = result.stderr + result.stdout;
  expect(result.code, "the release negative must fail generation").not.toBe(0);
  expect(text).toContain("CFRelease is ARC-managed in Swift");
});

test("B2 refuses takeRetainedValue by default", () => {
  const result = run([
    "haxe", "tests/swift-ownership-check/check-retained-negative.hxml",
    "-D", `swift-output=${out}/retained-negative`,
    "-D", `swift-test-output=${out}/retained-negative-tests`,
  ]);
  const text = result.stderr + result.stdout;
  expect(result.code, "the retained negative must fail generation").not.toBe(0);
  expect(text).toContain("takeRetainedValue is refused by default");
});
test("C builds CF containers from the constant bridge", async () => {
  const generate = run([
    "haxe", "tests/swift-ownership-check/check-c.hxml",
    "-D", `swift-output=${out}/c-gen`,
    "-D", `swift-test-output=${out}/c-tests`,
  ]);
  expect(generate.code, generate.stderr || generate.stdout).toBe(0);

  const sources = (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: `${out}/c-gen` }))).sort();
  const all = (await Promise.all(sources.map((path) => Bun.file(`${out}/c-gen/${path}`).text()))).join("\n");
  for (const banned of ["CFRelease", "CFRetain", "CGContextRelease", "CGColorSpaceRelease", "CGPathRelease"])
    expect(all, `generated tree must not call ${banned}`).not.toContain(banned);
  expect(all).toContain("withUnsafePointer(to: kCFTypeDictionaryKeyCallBacks)");
  expect(all).toContain("withUnsafePointer(to: kCFTypeDictionaryValueCallBacks)");
  expect(all).toContain("withUnsafePointer(to: kCFTypeArrayCallBacks)");
  expect(all).toContain("CFDictionaryCreate(");
  expect(all).toContain("CFArrayCreate(");
  expect(all).toContain("CFNumberCreate(");
});

test("a bridge value template with arbitrary code is rejected", () => {
  const result = run([
    "haxe", "tests/swift-ownership-check/check-bridge-code-negative.hxml",
    "-D", `swift-output=${out}/bridge-code`,
    "-D", `swift-test-output=${out}/bridge-code-tests`,
  ]);
  const text = result.stderr + result.stdout;
  expect(result.code, "the arbitrary-code bridge must fail generation").not.toBe(0);
  expect(text).toContain("value template must reference $0 or be a declared Swift constant");
});

test("a misspelled Swift constant is rejected at generation time", () => {
  const result = run([
    "haxe", "tests/swift-ownership-check/check-bridge-name-negative.hxml",
    "-D", `swift-output=${out}/bridge-name`,
    "-D", `swift-test-output=${out}/bridge-name-tests`,
  ]);
  const text = result.stderr + result.stdout;
  expect(result.code, "the misspelled constant must fail generation").not.toBe(0);
  expect(text).toContain("no declaration for Swift constant kCFTypeArrayCallBackz");
});
