import { describe, expect, test } from "bun:test";
import * as path from "node:path";

/**
 * Feature spec 23: the TypeScript target rejects float-precision=f32 at
 * plugin registration. number is binary64 with no binary32 alias in the
 * language, so the f32 configuration has no faithful lowering; the rejection must
 * fire before any type rendering, so a compile with the define fails and
 * names the reason.
 */
describe("float precision switch on the TypeScript target", () => {
  test("float-precision=f32 aborts the TS compile with the startup error", async () => {
    const repoRoot = path.resolve(__dirname, "../..");
    const proc = Bun.spawn(["haxe", "examples/ts.hxml", "-D", "float-precision=f32"], {
      cwd: repoRoot,
      stdout: "pipe",
      stderr: "pipe",
    });
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);

    expect(exitCode).not.toBe(0);
    expect(stderr).toContain("float-precision=f32 is not available on the TypeScript target");
    expect(stderr).toContain("number is binary64");
  });
});
