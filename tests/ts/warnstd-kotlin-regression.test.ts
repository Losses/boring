import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * R1 warn-zero regression pins (warnstd seat r2): each test reads the
 * generated Kotlin tree for one minimal mechanism sample under
 * samples/boring and asserts on the generated text itself.
 *
 * Negative-validation status: the DeclaredFieldNonNull, CharCodeNoToString
 * and NullArmStatementFold assertions were negative-validated by
 * regenerating against the pre-fix kotlincompiler emitter (7ee358ca~1)
 * and confirming they go red (captured outputs in
 * .tq-logs/warnstd/seats/r2.log). The guardedNonNullTernary elvis test
 * is a shape-only test: no pre-fix emitter shape that flips it red was
 * reached, so it holds the current rendered text but does NOT prove a
 * regression would be caught.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/kotlin/gen/boring", name), "utf8");

describe("warnstd kotlin regression samples", () => {
  test("DeclaredFieldNonNull: widened chain read keeps one extraction, drops the hop safe call and trailing force", () => {
    const out = gen("WidenedFieldNonNull.kt");
    expect(out).toContain("return r!!.next.count");
    expect(out).not.toContain("?.count");
    expect(out).not.toContain("next.count!!");
  });

  test("CharCodeNoToString: the fromCharCode template drops the redundant toString on its String branch", () => {
    const out = gen("FromCharCodeToString.kt");
    expect(out).toContain(".toChar()).toString()");
    expect(out).not.toContain("toChars((code))).toString()");
  });

  test("NullArmStatementFold: statement-position shift/pop renders as guarded statements, not an if-else expression", () => {
    const out = gen("ShiftPopStatement.kt");
    expect(out).toContain("if (!(items.isEmpty())) items.removeAt(items.lastIndex)");
    expect(out).toContain("if (!(items.isEmpty())) items.removeAt(0)");
    expect(out).not.toContain("else");
  });

  test("guardedNonNullTernary elvis wrap: proven non-null member reads stay on the non-null path (shape test, no negative validation)", () => {
    const out = gen("GuardedNonNullTernaryElvis.kt");
    expect(out).toContain("return r!!.size");
    expect(out).not.toContain("size!!");
  });
});
