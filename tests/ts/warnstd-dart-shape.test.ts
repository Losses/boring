import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * FlowPromotedDedupe is a Flow shape snapshot for the promotion-scope
 * mechanism (478b3835): it pins promoted text patterns across
 * statements, branch merge, and closure unwrap. r2.log recorded
 * pre==post for these minimal shapes
 * (.tq-logs/warnstd/seats/r2.log) — the check asserts current
 * rendered text but is not a validated degradation guard (no
 * negative control).
 *
 * This file holds only shape snapshots. Validated regression guards
 * remain in warnstd-dart-regression.test.ts.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/dart/gen/lib/boring", name), "utf8");

describe("warnstd dart shape snapshots", () => {
  test("flow-promoted reads stay unwrapped across statements, a branch merge and a closure (shape test, no negative validation)", () => {
    const out = gen("flow_promoted_dedupe.dart");
    expect(out).toContain("final n = r.length;");
    expect(out).toContain("return n + r.length;");
    expect(out).toContain("final f = () => r.length;");
    expect(out).not.toContain("r!");
  });
});