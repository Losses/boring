import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * R4.2 warn-zero TS regression pins — warn/ts3 criterion 5.
 *
 * Two families, two fixtures under samples/boring/, one test file.
 *
 * ## Fixture → root cause
 *
 *   NullableIntCompare.hx        TS18047    r42 A8-A11 / cluster C4
 *   NullableArrayElemArg.hx      TS2322     r42 A2-A5  / cluster C1
 *
 * ## Haxe type-check verdict (Haxe 4.3.7)
 *
 * Both fixture bodies compile in Haxe without error.  Null<T> is
 * permissively unifiable with T — the Haxe type checker does NOT
 * narrow the nullable references.  See .tq-logs/viii/haxe-typecheck-
 * probe/ for the probe sources and Haxe -js output.
 *
 * ## TS emitter gap (pre-fix)
 *
 * TsType.hx:37 renders Null<T> → `T | null`.  TsExpr emits bare
 * identifiers for TLocal references in comparison operands and
 * array-literal elements, without a non-null assertion.  Generated
 * TS (pre-fix) and tsc 5.9.3 --strict output:
 *
 *   NullableIntCompare.ts:
 *     code >= 48 && code <= 57         ← code: number | null
 *     → TS18047 'code' is possibly 'null'.  (×2)
 *
 *   NullableArrayElemArg.ts:
 *     consume([atom])                  ← atom: Atom | null
 *     → TS2322 Type '(Atom | null)[]' is not assignable to type 'Atom[]'.
 *
 * ## Expected post-fix TS (asserted below)
 *
 *   NullableIntCompare.ts:
 *     code! >= 48 && code <= 57        ← first ref !, second narrowed
 *     → 0 errors
 *
 *   NullableArrayElemArg.ts:
 *     consume([atom!])                 ← element unwrapped
 *     → 0 errors
 *
 * `!` is an erased type assertion (Haxe non-null → TS non-null).  It
 * does not change runtime behavior: `null >= 48` → false (null coerces
 * to 0), and `[null].length > 0` → true.  Haxe's own -js output for
 * these exact bodies produces the same runtime values.
 *
 * ## Null / non-null input behavior (proven by Haxe -js execution)
 *
 *   isDigit(null)  → false     pass(null)       → true
 *   isDigit(48)    → true      pass(new Atom()) → true
 *   isDigit(57)    → true      consume([])      → false
 *   isDigit(47)    → false
 *   isDigit(58)    → false
 *   isDigit(52)    → true
 *
 * ## Handoff for formal Nix verification
 *
 *   1. nix develop -c driver.js gen ts
 *      (regenerates reference/ts/gen/boring/)
 *   2. bun test tests/ts/warnstd-ts-regression.test.ts
 *      → shape tests: pass if the fix is in place
 *      → behavior tests: pass if generated modules are importable
 *   3. npx tsc --strict --noEmit --target esnext --moduleResolution bundler
 *      reference/ts/gen/boring/NullableIntCompare.ts
 *      → pre-fix: TS18047 ×2   post-fix: 0 errors
 *   4. npx tsc --strict --noEmit --target esnext --moduleResolution bundler
 *      reference/ts/gen/boring/NullableArrayElemArg.ts
 *      → pre-fix: TS2322 ×1    post-fix: 0 errors
 *
 * When generated artifacts are absent, all tests fail with ENOENT
 * (fs.readFileSync / dynamic import), which satisfies the "缺生成物
 * 必须失败不跳过" requirement — no skipped test, no silent pass.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/ts/gen/boring", name), "utf8");

const genModule = async (name: string): Promise<Record<string, any>> => {
  const mod = await import(path.resolve(import.meta.dir, "../../reference/ts/gen/boring", name));
  return mod as Record<string, any>;
};

describe("warnstd ts regression samples", () => {
  // ── shape assertions ──

  test("NullableIntCompare shape: Null<Int> comparison carries code! (TS18047 → 0 after fix)", () => {
    const out = gen("NullableIntCompare.ts");
    // Signature: parameter type stays nullable.
    expect(out).toContain("code: number | null");
    // Post-fix: first nullable reference gets `!`; tsc sees `number`.
    expect(out).toContain("code! >= 48");
    // Pre-fix broken shape must be absent.
    expect(out).not.toContain("code >= 48");
  });

  test("NullableArrayElemArg shape: nullable array element unwraps (TS2322 → 0 after fix)", () => {
    const out = gen("NullableArrayElemArg.ts");
    // Signature: parameter type stays nullable.
    expect(out).toContain("atom: Atom | null");
    // Post-fix: element carries `!` so the array is `Atom[]`.
    expect(out).toContain("[atom!]");
    // Pre-fix broken shape must be absent.
    expect(out).not.toContain("[atom]");
  });

  // ── behavior assertions (Haxe -js ground truth, `!` erased) ──

  test("NullableIntCompare runtime: isDigit preserves Haxe semantics (null→false, boundaries inclusive)", async () => {
    const { NullableIntCompare } = await genModule("NullableIntCompare.ts");
    // null is not a digit
    expect(NullableIntCompare.isDigit(null)).toBe(false);
    // inclusive boundaries: '0'=48, '9'=57
    expect(NullableIntCompare.isDigit(48)).toBe(true);
    expect(NullableIntCompare.isDigit(57)).toBe(true);
    // outside boundaries: '/'=47, ':'=58
    expect(NullableIntCompare.isDigit(47)).toBe(false);
    expect(NullableIntCompare.isDigit(58)).toBe(false);
    // interior: '4'=52
    expect(NullableIntCompare.isDigit(52)).toBe(true);
  });

  test("NullableArrayElemArg runtime: pass preserves Haxe semantics (null element counts, empty array is false)", async () => {
    const { NullableArrayElemArg, Atom } = await genModule("NullableArrayElemArg.ts");
    // null element: [null].length > 0 → true (Haxe -js identical)
    expect(NullableArrayElemArg.pass(null)).toBe(true);
    // non-null element
    expect(NullableArrayElemArg.pass(new Atom())).toBe(true);
    // empty array
    expect(NullableArrayElemArg.consume([])).toBe(false);
  });
});