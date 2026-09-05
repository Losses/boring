import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Lowered shape of the platform modules (docs/specs/stdlib/17).
 *
 * The platform modules of stdlib/17 lower their statics inline at the
 * call site, so the host access sits inside the lowered body and the
 * calling file gains no top-level `node:` import. When no host loader
 * exists (a browser) the call raises the fixed unavailability message.
 * The browser arm cannot run in this suite, so these tests pin the
 * lowered branch shape by textual assertion on the generated tree.
 */

const genDir = path.resolve(__dirname, "../../reference/ts/gen");

function readGenerated(relative: string): string {
  return fs.readFileSync(path.join(genDir, relative), "utf8");
}

describe("std.Fs lowering", () => {
  test("node:fs loads lazily through require inside each call body", () => {
    const source = readGenerated("boring/PlatformOps.ts");
    expect(source).toContain('require("node:fs")');
    // The loader probe and the fs access share one body per call; no
    // top-level node: import specifier appears.
    expect(source).not.toMatch(/^import .* from "node:/m);
    expect(source).not.toMatch(/from "node:fs"/);
  });

  test("a host without require raises the fixed unavailability message", () => {
    const source = readGenerated("boring/PlatformOps.ts");
    expect(source).toContain('throw new Error("std.Fs is not available on this host")');
  });
});

describe("std.Env lowering", () => {
  test("a browser host maps to localStorage with a null missing key", () => {
    const source = readGenerated("boring/PlatformOps.ts");
    expect(source).toContain('typeof localStorage !== "undefined"');
    expect(source).toContain("localStorage.getItem(k)");
    // The absent key reads as null (the direct Null<String> match).
    expect(source).toContain("?? null");
  });

  test("a node host maps to process.env behind a presence probe", () => {
    const source = readGenerated("boring/PlatformOps.ts");
    expect(source).toContain('typeof process !== "undefined"');
    expect(source).toContain("process.env[k]");
  });
});

describe("std.Process.args lowering", () => {
  test("reads process.argv.slice(2) lazily behind a presence probe", () => {
    const source = readGenerated("boring/PlatformOps.ts");
    expect(source).toContain("process.argv");
    expect(source).toContain(".slice(2)");
  });
});
