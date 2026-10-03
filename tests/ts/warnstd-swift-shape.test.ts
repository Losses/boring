import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * ClassInstanceLocalLet and UnusedLocalNaming are shape snapshots:
 * no pre-fix emitter shape that flips them red was reached, so they
 * hold the current rendered text but do NOT prove a regression
 * would be caught.
 *
 * This file holds only shape snapshots. Validated regression guards
 * remain in warnstd-swift-regression.test.ts.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/swift/gen/boring", name), "utf8");

describe("warnstd swift shape snapshots", () => {
  test("ClassInstanceLocalLet: a never-reassigned class-instance local declares let (shape test, no negative validation)", () => {
    const out = gen("ClassInstanceLocalLet.swift");
    expect(out).toContain("let inst = ClassInstanceLocalLet()");
    expect(out).not.toContain("var inst");
  });

  test("UnusedLocalNaming: a local the emitter proves unmentioned renders nothing (shape test, no negative validation)", () => {
    const out = gen("UnusedSwiftBinding.swift");
    expect(out).not.toContain("var unused");
    expect(out).not.toContain("let unused");
  });
});