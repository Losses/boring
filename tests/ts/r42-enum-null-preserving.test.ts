import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * r42 enum null-preserving QName candidate.
 *
 * The tests read the generated tree of
 * `samples/boring/EnumQNameNullPreservingFixture.hx`. That tree is
 * produced by the reflaxe TypeScript target when `bun run verify`
 * regenerates `reference/ts/gen`. Until that run happens the read
 * throws ENOENT and the case fails, so a missing tree never reads as
 * a pass; the failure names the exact file to regenerate.
 *
 * The `!` asserted below is a TypeScript non-null assertion
 * (type-level, erased). It does not add a runtime guard, and the
 * runtime TypeError on a null receiver is unchanged from the pre-fix
 * state.
 */
const gen = fs.readFileSync(
  path.resolve(
    import.meta.dir,
    "../../reference/ts/gen/boring/EnumQNameNullPreservingFixture.ts",
  ),
  "utf8",
);

describe("r42 enum null-preserving QName candidate", () => {
  test("kindOfLookup emits ! before .kind on a createEnum(QLookup) result (discriminant)", () => {
    // QName on a createEnum(QLookup) result: the *OfName helper returns
    // R42ShapeTag | null, and the emitter must insert ! before .kind so
    // TypeScript accepts the member read. The old emitter produced `.kind`
    // without `!` and triggered TS2531; the fixed emitter produces `!.kind`.
    expect(gen).toContain("r42ShapeTagOfName(name)!.kind");
  });

  test("kindOfValue emits .kind on a plain non-null enum with no QName assertion", () => {
    // QName on a non-null enum value renders `.kind` with no extra `!`
    // from the QName branch.
    expect(gen).toContain("return tag.kind;");
  });

  test("kindOfCoalesce parenthesizes the ternary receiver before .kind", () => {
    // QName on a null-coalescing ternary: the receiver is a low-precedence
    // TIf, so the QName branch wraps it in parentheses.  The guarded ternary
    // already ships its own inner parens `(c ? a : b)`, and the wrap adds
    // one deliberate outer layer so `.kind` binds to the whole ternary.
    expect(gen).toContain(
      "((maybe === null ? R42ShapeTag.Alpha : maybe)).kind",
    );
  });

  test("no double assertion (!!) appears anywhere in the fixture output", () => {
    expect(gen).not.toMatch(/\!\!\.kind/);
  });

  test("the *OfName lookup helper retains the nullable return contract", () => {
    // The *OfName declaration and null fallback are frozen.
    expect(gen).toContain(
      "r42ShapeTagOfName(name: string): R42ShapeTag | null",
    );
    expect(gen).toContain("return null;");
  });
});
