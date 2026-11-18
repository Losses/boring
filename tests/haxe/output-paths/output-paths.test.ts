import { describe, expect, test } from "bun:test";
import { join, resolve } from "node:path";

/**
 * Collected driver for the output-path fixture. The compile smoke runs
 * `output-paths.hxml` too; this test is what makes the fixture reachable from
 * `bun test tests/`: tests/fixture-reachability.test.ts counts a fixture as
 * watched only when a collected test lives in its directory or names its path,
 * and a fixture with a runner outside that set would raise the recorded
 * uncollected count.
 */

const ROOT = resolve(import.meta.dir, "..", "..", "..");

describe("swift output tree relativization", () => {
  test("the fixture's windows, posix and drive cases pass under --interp", async () => {
    const proc = Bun.spawn(["haxe", join(import.meta.dir, "output-paths.hxml")], {
      cwd: ROOT,
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    const code = await proc.exited;
    const output = stdout + stderr;
    expect(output).toContain("output-paths-ok");
    expect(code).toBe(0);
  });
});
