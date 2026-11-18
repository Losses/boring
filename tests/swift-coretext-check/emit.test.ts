import { expect, test } from "bun:test";

// The generation half of the permanent Swift C interop check. It pins the
// emitted text for the three mechanisms the Apple cutover needs: a
// declaration-scoped framework import, a String -> CFString representation
// bridge (with and without a lifetime bracket), and a C enum spelling. The
// compile/run half is tests/swift-coretext-check/run.sh on macOS; this test
// keeps the shapes honest on every platform the collected suite runs.

const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_SWIFT_C_INTEROP_OUT ?? `${root}/out/swift-c-interop/test-${crypto.randomUUID()}`;

async function run(command: string[], label: string): Promise<string> {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  await Bun.write(`${out}/${label}.stdout.log`, stdout);
  await Bun.write(`${out}/${label}.stderr.log`, stderr);
  expect(result.exitCode, `${label}: ${stderr || stdout}`).toBe(0);
  return stdout;
}

async function generate(gen: string, tests: string, label: string): Promise<void> {
  await run(
    ["haxe", "tests/swift-coretext-check/check.hxml", "-D", `swift-output=${gen}`, "-D", `swift-test-output=${tests}`],
    label,
  );
}

async function sourceList(base: string): Promise<Array<string>> {
  return (await Array.fromAsync(new Bun.Glob("**/*.swift").scan({ cwd: base }))).sort();
}

async function findSource(base: string, name: string): Promise<string> {
  const matches = (await sourceList(base)).filter((path) => path.endsWith("/" + name));
  expect(matches.length, `expected exactly one generated ${name}, found ${matches.join(", ")}`).toBe(1);
  return `${base}/${matches[0]}`;
}

test("the three C interop mechanisms emit their declared shapes", async () => {
  const existing = Bun.spawnSync(["test", "-e", out], { cwd: root });
  expect(existing.exitCode, `focused output directory already exists: ${out}`).toBe(1);
  Bun.spawnSync(["mkdir", "-p", out]);

  const gen = `${out}/gen`;
  const tests = `${out}/gen-tests`;
  await generate(gen, tests, "generate");

  const supportPath = await findSource(out, "CoreTextMetricsSupport.swift");
  const support = await Bun.file(supportPath).text();
  // 1. Declaration-scoped framework import.
  expect(support.match(/^import CoreText$/gm)?.length ?? 0, "the import is emitted once per declaration, not once per mention").toBe(1);
  // 2a. String -> CFString value bridge.
  expect(support).toContain("String(decoding: name, as: UTF16.self) as CFString");
  // 2b. Lifetime brackets: a C string and a UTF-16 buffer pointer.
  expect(support).toContain("String(decoding: name, as: UTF16.self).withCString { ");
  expect(support).toContain("units.withUnsafeBufferPointer { ");
  expect(support).toContain(".baseAddress!");
  // 3. C enum spellings: a CF_ENUM member and an initializer-shaped seam.
  expect(support).toContain("CTFontUIFontType.system");
  expect(support).toContain("CFStringBuiltInEncodings.UTF8.rawValue");
  expect(support).toContain("Int(Int32(units.count))");

  // 1 (scope): the declared import stays on the files whose declarations asked
  // for it; a module that names no platform symbol carries no line.
  const unrelatedPath = await findSource(out, "Unrelated.swift");
  const unrelated = await Bun.file(unrelatedPath).text();
  expect(unrelated).not.toContain("import CoreText");
  const testPath = await findSource(out, "CoreTextMetricsTests.swift");
  expect(await Bun.file(testPath).text()).toContain("import CoreText");
  for (const base of [gen, tests]) {
    for (const relative of await sourceList(base)) {
      if (relative.endsWith("/CoreTextMetricsSupport.swift") || relative.endsWith("/CoreTextMetricsTests.swift"))
        continue;
      expect(await Bun.file(`${base}/${relative}`).text(), `${relative} must not inherit CoreText`).not.toContain("import CoreText");
    }
  }

  // Repeated generation is byte-identical, so the mapped text is stable.
  const repeated = `${out}/gen-repeat`;
  const repeatedTests = `${out}/gen-tests-repeat`;
  await generate(repeated, repeatedTests, "generate-repeat");
  const first = await sourceList(gen);
  const firstTests = await sourceList(tests);
  expect(await sourceList(repeated)).toEqual(first);
  expect(await sourceList(repeatedTests)).toEqual(firstTests);
  for (const relative of first)
    expect(await Bun.file(`${repeated}/${relative}`).text(), `repeat generation changed ${relative}`).toBe(await Bun.file(`${gen}/${relative}`).text());
  for (const relative of firstTests)
    expect(await Bun.file(`${repeatedTests}/${relative}`).text(), `repeat generation changed ${relative}`).toBe(await Bun.file(`${tests}/${relative}`).text());
});
