import { expect, test } from "bun:test";

/**
 * Regression for the cast-laundered optional ternary arm
 * (samples/tests/TestLitEdgeTests.hx:11, P09 pin 77bc5d47).
 *
 * A nullable field read is compared against null and the non-null arm is a
 * transparent Haxe cast `(field : Float)`. Haxe unifies the cast with the
 * non-null leaf type, so the ternary types as `Float`, but `castText`
 * lowers the cast to the bare field read, which is still `Double?` in
 * Swift. The non-optional ternary must force-unwrap that arm; before the
 * fix the generated test executable failed with
 * "value of optional type 'Double?' must be unwrapped" at
 * reference/swift/gen-tests/tests/TestLitEdgeTests.swift:9:73.
 *
 * The fixture also pins the boundary: a local subject renders through the
 * nil-merge path (`??`), and an optional-typed whole must NOT unwrap.
 */
const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_LIT_CAST_OPTIONAL_OUT ?? `${root}/out/swift-cast-laundered-optional/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;
const moduleFile = `${generated}/litcast/LitCastOptionalOps.swift`;

test("a null-guarded ternary arm laundered by a transparent cast unwraps", async () => {
  await Bun.$`mkdir -p ${out}`;

  const generate = Bun.spawnSync(
    ["haxe", "tests/swift-cast-laundered-optional/swift.hxml", "-D", `swift-output=${generated}`],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  await Bun.write(`${out}/generate.stdout.log`, generate.stdout.toString());
  await Bun.write(`${out}/generate.stderr.log`, generate.stderr.toString());
  expect(
    generate.exitCode,
    `generate: ${generate.stderr.toString() || generate.stdout.toString()}`,
  ).toBe(0);

  const source = await Bun.file(moduleFile).text();

  // The failing shape: the array-element nullable field arm force-unwraps.
  expect(source, "cast-laundered array-element arm unwraps").toContain(
    "(LitCastOptionalOps.edges()[Int(0)].inlineStart == nil ? -1.0 : (LitCastOptionalOps.edges()[Int(0)].inlineStart)!)",
  );
  // A local subject is a nil-merge site, not the ternary path.
  expect(source, "local subject coalesces").toContain("return e.inlineStart ?? -1.0");
  // The whole expression stays optional here, so neither arm may unwrap.
  expect(source, "optional whole keeps both arms optional").toContain(
    "(LitCastOptionalOps.edges()[Int(0)].inlineStart == nil ? nil : LitCastOptionalOps.edges()[Int(0)].inlineStart)",
  );

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
