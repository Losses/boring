import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Reachability + shape guard for the fs-failure-kinds fixture
 * (tests/haxe/fs-failure-kinds/). The runtime readings are produced by
 * `EV=<evidence dir> bash tests/haxe/fs-failure-kinds/run-stages.sh ts kotlin dart`;
 * this test keeps the fixture collected and pins the authored expectation and
 * the cross-target identity table against accidental edits.
 */
const FIXTURE = resolve(import.meta.dir, "../haxe/fs-failure-kinds");

function read(rel: string): string {
  return readFileSync(join(FIXTURE, rel), "utf8");
}

describe("std.Fs failure identity fixture", () => {
  test("the authored expectation lists the six readings in order", () => {
    expect(read("expected.txt")).toBe(
      [
        "missing-read=NotFound|readText",
        "not-a-directory-read=NotDirectory|readText",
        "write-over-directory=IsDirectory|writeText",
        "predicates-missing=false|false",
        "manual-catch=NotFound|readText",
        "denied-read=PermissionDenied|readText",
        "",
      ].join("\n"),
    );
  });

  test("the oracle binds all eight normalized kinds and the fallible operations", () => {
    const oracle = read("fsfail/FsFailOracle.hx");
    for (const kind of [
      "NotFound",
      "PermissionDenied",
      "NotDirectory",
      "AlreadyExists",
      "InvalidInput",
      "IsDirectory",
      "Unavailable",
      "Other",
    ]) {
      expect(oracle).toContain(`case ${kind}(`);
    }
    expect(oracle).toContain("Fs.readText(path)");
    expect(oracle).toContain("Fs.writeText(path,");
    expect(oracle).toContain("Fs.exists(path)");
    expect(oracle).toContain("Fs.isDirectory(path)");
  });

  test("a stage runner drives the fixture on the three runnable targets", () => {
    const runner = read("run-stages.sh");
    for (const target of ["ts", "kotlin", "dart"]) {
      expect(runner).toContain(`${target})`);
    }
  });
});
