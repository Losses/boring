import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

/**
 * P5.6 Swift I2 guard.
 *
 * SwiftCoerce.coerce is the single sanctioned emission point for the postfix
 * force-unwrap x + "!" and the nil-coalescing + " ?? ".  Any suffix + "!"
 * or + " ?? " emitted by files other than SwiftCoerce.hx is a conversion
 * bypass that the guard must pin.
 *
 * Swift ! is also a prefix logical-NOT operator, which is emitted as
 * "!" + x.  The guard only counts the SUFFIX x + "!" form (the regex
 * requires + BEFORE the literal), so "!" + x is never flagged.
 *
 * The guard text-scans every swiftcompiler .hx file outside SwiftCoerce.hx,
 * collects the exact file:line set of postfix-! and nil-coalescing emission
 * lines, and asserts it equals KNOWN_OUTSIDE.  Assertions:
 *
 *   1. SwiftCoerce.hx contains exactly one "function coerce(" declaration,
 *      so renaming the sole entry point breaks the guard loudly.
 *   2. The found set matches KNOWN_OUTSIDE exactly (rc=0 on the current tree).
 *   3. Injecting one fresh + "!" bypass into the in-memory copy of
 *      SwiftExpr.hx produces exactly one violation (rc!=0), proving the
 *      guard is not vacuous.
 */

const root = path.resolve(import.meta.dir, "../..");
const compilerDir = path.join(root, "packages/compiler/reflaxe/swift/swiftcompiler");
const COERCE_FILE = "SwiftCoerce.hx";

/**
 * Known outside-coerce suffix-! and nil-coalescing emission sites on the
 * current tree.  Each entry is File.hx:line, one per line that emits
 * x + "!" (postfix force-unwrap) or + " ?? " (nil-coalescing) outside
 * SwiftCoerce.hx.
 *
 * When a migration removes a site, the guard reports it as
 * "expected site migrated/removed" and the allowlist must be refreshed to
 * the new reality.  When a new bypass is added, the guard reports
 * "new bypass outside coerce".  Both directions force deliberate maintenance
 * instead of silent drift.
 */
const KNOWN_OUTSIDE: string[] = [
  // postfix force-unwrap x + "!"
  "SwiftDecl.hx:623",
  "SwiftExpr.hx:2170",
  "SwiftExpr.hx:3138",
  "SwiftExpr.hx:3158",
  "SwiftExpr.hx:3162",
  "SwiftExpr.hx:3167",
  "SwiftExpr.hx:3170",
  "SwiftExpr.hx:4662",
  "SwiftExpr.hx:5150",
  "SwiftExpr.hx:5311",
  "SwiftExpr.hx:5461",
  "SwiftExpr.hx:6434",
  // nil-coalescing + " ?? "
  "SwiftDecl.hx:1002",
  "SwiftDecl.hx:1014",
  "SwiftExpr.hx:347",
  "SwiftExpr.hx:1687",
  "SwiftExpr.hx:1739",
  "SwiftExpr.hx:2308",
  "SwiftExpr.hx:2433",
  "SwiftExpr.hx:2920",
  "SwiftExpr.hx:5193",
  "SwiftExpr.hx:5206",
  "SwiftExpr.hx:5296",
  "SwiftExpr.hx:5309",
];

// Postfix force-unwrap: value + "!".  Requires + BEFORE the literal so the
// prefix logical-NOT form "!" + x is never matched.
const POSTFIX_BANG = /\+ *"!"/;

// Nil-coalescing emission: value + " ?? ".  Also requires + BEFORE so
// sniffers like lastIndexOf(" ?? ") (SwiftExpr.hx:2288) are excluded.
const COALESCE = /\+ *" *\? *\? *"/;

type Sources = Record<string, string[]>;

function readSources(): Sources {
  const sources: Sources = {};
  for (const name of readdirSync(compilerDir)) {
    if (!name.endsWith(".hx")) continue;
    sources[name] = readFileSync(path.join(compilerDir, name), "utf8").split("\n");
  }
  return sources;
}

// Count "function coerce(" declarations in SwiftCoerce.hx.  Must equal 1.
function coerceDeclarationCount(sources: Sources): number {
  const lines = sources[COERCE_FILE] ?? [];
  let count = 0;
  for (const line of lines) if (/function\s+coerce\s*\(/.test(line)) count++;
  return count;
}

// Collect every file:line in swiftcompiler *.hx (excluding SwiftCoerce.hx)
// whose text matches POSTFIX_BANG or COALESCE.  Returns a sorted array.
function outsideCoerceSites(sources: Sources): string[] {
  const sites = new Set<string>();
  for (const name of Object.keys(sources).sort()) {
    if (name === COERCE_FILE) continue;
    const lines = sources[name];
    lines.forEach((line, index) => {
      const site = name + ":" + (index + 1);
      if (POSTFIX_BANG.test(line)) sites.add(site);
      if (COALESCE.test(line)) sites.add(site);
    });
  }
  return Array.from(sites).sort();
}

// Compare the set of outside-coerce sites against KNOWN_OUTSIDE.  Returns an
// empty array when the tree exactly matches the allowlist (rc=0).  Otherwise
// every mismatch gets one diagnostic line (rc!=0).
function violations(sites: string[], coerceCount: number): string[] {
  const v: string[] = [];
  if (coerceCount !== 1) {
    v.push("coerce exists " + coerceCount + " time(s) in " + COERCE_FILE + " (expected exactly 1; rename breaks guard)");
  }
  const known = new Set(KNOWN_OUTSIDE);
  const found = new Set(sites);
  for (const site of found) {
    if (!known.has(site)) v.push("new bypass outside coerce: " + site);
  }
  for (const site of known) {
    if (!found.has(site)) {
      v.push("expected site migrated/removed (refresh allowlist): " + site);
    }
  }
  return v;
}

test("P5.6 guard: current tree has no outside-coerce bypass (rc=0)", () => {
  const sources = readSources();
  const sites = outsideCoerceSites(sources);
  const v = violations(sites, coerceDeclarationCount(sources));
  expect(
    v,
    "guard must report zero violations on the current tree\n" + v.join("\n"),
  ).toEqual([]);
});

test('P5.6 guard: injecting one fresh postfix +"!" bypass is caught (rc!=0)', () => {
  const sources = readSources();
  const exprLines = sources["SwiftExpr.hx"];
  const injectedLine = exprLines.length + 1;
  const modified: Sources = {
    ...sources,
    "SwiftExpr.hx": [
      ...exprLines,
      'class GuardInjectedBypass { static function emit(value:String):String return value + "!"; }',
    ],
  };
  const sites = outsideCoerceSites(modified);
  const v = violations(sites, coerceDeclarationCount(modified));
  expect(v).toEqual(["new bypass outside coerce: SwiftExpr.hx:" + injectedLine]);
});

