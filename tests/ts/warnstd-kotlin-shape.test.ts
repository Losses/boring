import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * guardedNonNullTernary elvis is a shape snapshot: the rendered
 * Kotlin text for this minimal mechanism pins the current emitter
 * output but has no pre-fix emitter shape that flips it red — it
 * holds the current rendered text but does NOT prove a regression
 * would be caught.
 *
 * This file holds only shape snapshots. Validated regression guards
 * remain in warnstd-kotlin-regression.test.ts.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/kotlin/gen/boring", name), "utf8");

describe("warnstd kotlin shape snapshots", () => {
  test("guardedNonNullTernary elvis wrap: proven non-null member reads stay on the non-null path (shape test, no negative validation)", () => {
    const out = gen("GuardedNonNullTernaryElvis.kt");
    expect(out).toContain("return r!!.size");
    expect(out).not.toContain("size!!");
  });
});