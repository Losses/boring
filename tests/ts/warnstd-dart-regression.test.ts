import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * FlowPromotedDedupe is a Flow shape check for the promotion-scope
 * mechanism (478b3835): it pins promoted text patterns across
 * statements, branch merge, and closure unwrap. r2.log recorded
 * pre==post for these minimal shapes
 * (.tq-logs/warnstd/seats/r2.log) — the check asserts current
 * behavior but is not a validated degradation guard.
 *
 * GuardTernaryArgNonNull is a behavior pin verified through VIII
 * negative-control experiments beyond the original r2.log check:
 *
 *   Mutation discrimination — four hand-authored fixture
 *   mutations under .tq-logs/viii/dart-pin-controls/
 *   negative-fixtures/ (old_shape, null_coalesce_variant,
 *   ternary_plus_coalesce, no_space_coalesce) are each correctly
 *   rejected by the full four-clause assertion set, proving the
 *   pin discriminates and is not tautological.
 *
 *   Historical backport —
 *   .tq-logs/viii/historical-dart-control/ holds archived
 *   controlled before/after artifacts showing the corresponding
 *   byte difference: 515b00c3~1 output (old shape with r! + !))
 *   vs 515b00c3 output (new shape, byte-identical to current HEAD
 *   reference). Generation logs are empty; no fresh replay was
 *   performed.
 *
 * The pin was updated from its pre-515b00c3 stale shape in
 * 0f5979bd (tightened not.toContain("??") to also reject no-
 * space coalesce). What is demonstrated is mutation
 * discrimination and, from the archived artifacts, the byte
 * difference across 515b00c3 for this specific fixture. No claim
 * is made that this would catch any future regression, and no
 * mechanism-level historical causal chain is asserted beyond the
 * recorded runs.
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
