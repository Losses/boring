import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * R1 warn-zero regression pins (warnstd seat r2): each test reads the
 * generated Dart tree for one minimal mechanism sample under
 * samples/boring and asserts on the generated text itself. These are
 * behavior pins for the promotion-scope and guard-ternary mechanisms
 * of 478b3835/d5cf10b2; minimal shapes that flip red against the
 * pre-fix emitters were not reached (see .tq-logs/warnstd/seats/r2.log),
 * so the assertions pin the promoted, fallback-free text.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/dart/gen/lib/boring", name), "utf8");

describe("warnstd dart regression samples", () => {
  test("flow-promoted reads stay unwrapped across statements, a branch merge and a closure", () => {
    const out = gen("flow_promoted_dedupe.dart");
    expect(out).toContain("final n = r.length;");
    expect(out).toContain("return n + r.length;");
    expect(out).toContain("final f = () => r.length;");
    expect(out).not.toContain("r!");
  });

  test("GuardTernaryArgNonNull: a guard-ternary argument carries no call-site fallback (behavior pin)", () => {
    const out = gen("guard_ternary_dead_fallback.dart");
    expect(out).toContain('take((r != null ? r : "x"))');
    expect(out).not.toContain("r!");
    expect(out).not.toContain("!)");
    expect(out).not.toContain("??");
  });
});
