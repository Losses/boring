import { expect, test } from "bun:test";

/**
 * Regression for the std.Fs host-edge Foundation import
 * (docs/specs/stdlib/17-platform-modules.md).
 *
 * A generated file that calls a fallible std.Fs operation carries the
 * boringFsError failure classifier, which reads NSError and
 * NSPOSIXErrorDomain. The pinned Swift 6.2.4 toolchain's
 * FoundationEssentials exports neither, so a header that imports only
 * FoundationEssentials produces "cannot find type 'NSError'" and
 * "cannot find 'NSPOSIXErrorDomain'" on the generated file. The header
 * must import Foundation as well.
 */
const root = `${import.meta.dir}/../..`;
const out = Bun.env.BORING_FS_FOUNDATION_IMPORT_OUT ?? `${root}/out/swift-fs-foundation-import/test-${crypto.randomUUID()}`;
const generated = `${out}/gen`;
const moduleFile = `${generated}/fsfnd/FsFoundationOps.swift`;
// Everything the fixture's generated file needs to typecheck: the Haxe
// exception base lives in Runtime.swift.
const typecheckInputs = [
  "fsfnd/FsFoundationOps.swift",
  "std/FsException.swift",
  "std/FsError.swift",
  "Runtime.swift",
];

test("a fallible std.Fs host edge imports Foundation and typechecks", async () => {
  await Bun.$`mkdir -p ${out}`;

  const generate = Bun.spawnSync(
    ["haxe", "tests/swift-fs-foundation-import/swift.hxml", "-D", `swift-output=${generated}`],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  await Bun.write(`${out}/generate.stdout.log`, generate.stdout.toString());
  await Bun.write(`${out}/generate.stderr.log`, generate.stderr.toString());
  expect(
    generate.exitCode,
    `generate: ${generate.stderr.toString() || generate.stdout.toString()}`,
  ).toBe(0);

  const source = await Bun.file(moduleFile).text();
  expect(source, "FoundationEssentials import arm").toMatch(
    /#if canImport\(FoundationEssentials\)\nimport FoundationEssentials\n#endif/,
  );
  expect(source, "Foundation import arm").toMatch(
    /#if canImport\(Foundation\)\nimport Foundation\n#endif/,
  );
  // Guard the fixture's own reach: if the classifier stops naming these
  // symbols the test would pass for the wrong reason.
  expect(source, "failure classifier reads NSError").toContain("as NSError");
  expect(source, "rename helper constructs NSPOSIXErrorDomain").toContain("NSPOSIXErrorDomain");

  const typecheck = Bun.spawnSync(
    ["swiftc", "-typecheck", ...typecheckInputs.map((f) => `${generated}/${f}`)],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  const diagnostics = typecheck.stderr.toString();
  await Bun.write(`${out}/typecheck.stderr.log`, diagnostics);
  await Bun.write(`${out}/typecheck.status`, `${typecheck.exitCode ?? 1}\n`);
  const errors = diagnostics.split("\n").filter((line) => line.includes(": error:"));
  expect(errors, `swiftc -typecheck: ${diagnostics || "no diagnostics"}`).toEqual([]);
  expect(diagnostics, "NSError/NSPOSIXErrorDomain must resolve").not.toMatch(
    /NSError|NSPOSIXErrorDomain/,
  );
  expect(typecheck.exitCode, `swiftc -typecheck: ${diagnostics || "no diagnostics"}`).toBe(0);
}, 120_000);
