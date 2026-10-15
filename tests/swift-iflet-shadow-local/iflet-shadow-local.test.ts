import { expect, test } from "bun:test";

/**
 * Regression for the if-let shadowed-local force-unwrap leak
 * (SwiftExpr.hx returnValue). An optional numeric local guarded by
 * 'if (x != null)' lowers to 'if let x = x'; the Swift binding is
 * non-optional inside the branch, so value uses must render bare or
 * through the Float conversion -- never 'x!', which would fail with
 * "cannot force unwrap value of non-optional type".
 *
 * The fixture spans the three site shapes the convergence must cover:
 * a bare return, an arithmetic operand, and a multi-use return.
 */
const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_IFLET_SHADOW_OUT ?? `${root}/out/swift-iflet-shadow-local/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;
const moduleFile = `${generated}/shadow/IfLetShadowLocal.swift`;

test("a shadowed optional local renders bare / Float-converted, never force-unwrapped", async () => {
  await Bun.$`mkdir -p ${out}`;

  const generate = Bun.spawnSync(
    ["haxe", "tests/swift-iflet-shadow-local/swift.hxml", "-D", `swift-output=${generated}`],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  await Bun.write(`${out}/generate.stdout.log`, generate.stdout.toString());
  await Bun.write(`${out}/generate.stderr.log`, generate.stderr.toString());
  expect(
    generate.exitCode,
    `generate: ${generate.stderr.toString() || generate.stdout.toString()}`,
  ).toBe(0);

  const source = await Bun.file(moduleFile).text();

  // The shadow binding is emitted in every function.
  expect(source, "shadow binding is emitted").toContain("if let x = x {");

  // Return site: the shadowed local goes through the Float conversion, not x!.
  expect(source, "return site is Float-converted, not force-unwrapped").toContain("return Double(x)");

  // Operand site: the shadowed local renders bare.
  expect(source, "operand site renders bare").toContain("return x + 1.0");

  // Multi-site: the shadowed local renders bare at both operand uses.
  expect(source, "multi-site renders bare").toContain("return x + x");

  // Discriminator: no force-unwrap is applied to the non-optional shadow.
  expect(source, "no force-unwrap on the shadowed local").not.toContain("x!");

  // Generation succeeded above; this proves the generated code typechecks.
  const typecheck = Bun.spawnSync(
    ["swiftc", "-typecheck", moduleFile, `${generated}/Runtime.swift`],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  const diagnostics = typecheck.stderr.toString();
  await Bun.write(`${out}/typecheck.stdout.log`, typecheck.stdout.toString());
  await Bun.write(`${out}/typecheck.stderr.log`, diagnostics);
  await Bun.write(`${out}/typecheck.status`, `${typecheck.exitCode ?? 1}\n`);
  expect(
    diagnostics.split("\n").filter((line) => line.includes(": error:")),
    `swiftc -typecheck: ${diagnostics || "no diagnostics"}`,
  ).toEqual([]);
  expect(typecheck.exitCode, `swiftc -typecheck: ${diagnostics || "no diagnostics"}`).toBe(0);
}, 120_000);

