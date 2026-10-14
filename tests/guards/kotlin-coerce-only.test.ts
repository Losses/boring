import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

/**
 * P3.3 Kotlin I2 guard.
 *
 * KotlinCoerce.coerce is the single sanctioned emission point for the
 * postfix non-null assertion x + "!!".  Any + "!!" emitted outside the
 * coerce function body is a conversion bypass that the guard must pin.
 *
 * The guard text-scans every kotlincompiler .hx file, locates the
 * KotlinCoerce.coerce function body boundary, and asserts that every
 * + "!!" emission OUTSIDE that body matches KNOWN_OUTSIDE exactly.
 *
 * It also text-scans KotlinExpr.hx (KE) for the P3.3 text-sniff read
 * patterns (indexOf("?."), indexOf("?: throw"), endsWith(x, "!!" | "?")) that
 * the criterion-1 grep targets.  P3.3b migrated the remaining 3 KE
 * sites to AST-level decisions, so KNOWN_TEXT_SNIFF is empty and the
 * guard enforces zero text-sniffs in KE.
 *
 * Assertions:
 *   1. KotlinCoerce.hx contains exactly one "function coerce(" declaration,
 *      so renaming the sole entry point breaks the guard loudly.
 *   2. The found + "!!" set matches KNOWN_OUTSIDE exactly (rc=0 on the
 *      current tree).
 *   3. The found KE text-sniff set matches KNOWN_TEXT_SNIFF exactly (rc=0 on
 *      the current tree).
 *   4. Injecting one fresh bypass of either kind into the in-memory copy
 *      produces exactly one violation (rc!=0), proving the guard is not
 *      vacuous.
 */

const root = path.resolve(import.meta.dir, "../..");
const compilerDir = path.join(root, "packages/compiler/reflaxe/kotlin/kotlincompiler");
const COERCE_FILE = "KotlinCoerce.hx";
const EXPR_FILE = "KotlinExpr.hx";

/**
 * Known outside-coerce + "!!" emission sites on the current tree.  Each
 * entry is File.hx:line, one per line that emits x + "!!" (postfix non-null
 * assertion) outside the coerce function body.
 *
 * These two KotlinExpr.hx sites are the "!!." access-extraction decision
 * sites: the renderer embeds the "!!" into the receiver text there (before
 * the "." member operator is appended), so they are legitimately outside
 * KotlinCoerce.coerce.  When a migration removes a site, the guard reports
 * "expected site migrated/removed"; when a new bypass is added, it reports
 * "new bypass outside coerce".
 */
const KNOWN_OUTSIDE: string[] = [
  "KotlinExpr.hx:4495", // receiverText for ?.length access extraction
  "KotlinExpr.hx:4564", // receiverText for property access extraction
];

// Postfix non-null assertion: value + "!!".  Requires + BEFORE the literal;
// Kotlin has no prefix "!!", so the suffix form is unambiguous.
const POSTFIX_BANG = /\+ *"!!"/;

// Text-sniff read pattern (criterion-1 grep): reading the already-rendered
// text to infer nullability.  Three alternatives: endsWith(x, "!!" | "?"),
// indexOf("?."), indexOf("?: throw").
const TEXT_SNIFF = /endsWith\([a-zA-Z]+, "(?:!!|\?)"\)|indexOf\("(?:\?\.|\?: throw)"\)/;

/**
 * P3.3b migrated all three remaining KE text-sniff sites to AST-level
 * decisions (the ?.-emission mirror in stringConcatOperand and the
 * AST-ified post-condition self-check plus enum-reflection lowering in
 * requiresNonNullCallArgument).  KNOWN_TEXT_SNIFF is empty, so the guard
 * enforces zero text-sniffs in KE.
 */
const KNOWN_TEXT_SNIFF: string[] = [];

type Sources = Record<string, string[]>;

function readSources(): Sources {
  const sources: Sources = {};
  for (const name of readdirSync(compilerDir)) {
    if (!name.endsWith(".hx")) continue;
    sources[name] = readFileSync(path.join(compilerDir, name), "utf8").split("\n");
  }
  return sources;
}

// Count "function coerce(" declarations in KotlinCoerce.hx.  Must equal 1.
function coerceDeclarationCount(sources: Sources): number {
  const lines = sources[COERCE_FILE] ?? [];
  let count = 0;
  for (const line of lines) if (/function\s+coerce\s*\(/.test(line)) count++;
  return count;
}

// Locate the coerce function body line range in KotlinCoerce.hx (1-based,
// inclusive).  Text-scans from the "function coerce(" declaration to the
// matching closing brace, skipping string literals and // line comments so
// a brace inside a literal/comment does not skew the depth.  Returns null
// when the declaration is absent, so a rename breaks the guard loudly.
function coerceBodyRange(sources: Sources): [number, number] | null {
  const lines = sources[COERCE_FILE] ?? [];
  const decl = lines.findIndex((l) => /function\s+coerce\s*\(/.test(l));
  if (decl < 0) return null;
  let open = -1;
  for (let i = decl; i < lines.length; i++) {
    if (lines[i].indexOf("{") >= 0) { open = i; break; }
  }
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < lines.length; i++) {
    depth += braceDelta(lines[i]);
    if (depth === 0) return [decl + 1, i + 1];
  }
  return null;
}

// Net brace balance of one line, ignoring braces inside "..." string
// literals and // line comments.  The coerce body contains no /* block
// comments, so a block-comment brace is treated as code (harmless today,
// documented as a text-scan limitation like the spec's risk note).
function braceDelta(line: string): number {
  let delta = 0;
  let inString = false;
  let inLineComment = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    const n = line[i + 1];
    if (inLineComment) break;
    if (inString) {
      if (c === "\\") { i++; continue; }
      if (c === '"') inString = false;
      continue;
    }
    if (c === "/" && n === "/") { inLineComment = true; i++; continue; }
    if (c === '"') { inString = true; continue; }
    if (c === "{") delta++;
    else if (c === "}") delta--;
  }
  return delta;
}

// Collect every file:line in kotlincompiler *.hx whose text matches
// POSTFIX_BANG, EXCLUDING the coerce function body range inside
// KotlinCoerce.hx.  Returns a sorted array.
function outsideCoerceSites(sources: Sources): string[] {
  const range = coerceBodyRange(sources);
  const cs = range ? range[0] : -1;
  const ce = range ? range[1] : -1;
  const sites = new Set<string>();
  for (const name of Object.keys(sources).sort()) {
    const lines = sources[name];
    lines.forEach((line, index) => {
      if (!POSTFIX_BANG.test(line)) return;
      const lineNo = index + 1;
      if (name === COERCE_FILE && cs <= lineNo && lineNo <= ce) return;
      sites.add(name + ":" + lineNo);
    });
  }
  return Array.from(sites).sort();
}

// Collect every KotlinExpr.hx line matching TEXT_SNIFF (KE only, per the
// criterion-1 grep target).  Returns a sorted array.
function textSniffSites(sources: Sources): string[] {
  const sites = new Set<string>();
  const lines = sources[EXPR_FILE] ?? [];
  lines.forEach((line, index) => {
    if (TEXT_SNIFF.test(line)) sites.add(EXPR_FILE + ":" + (index + 1));
  });
  return Array.from(sites).sort();
}

// Compare the found + "!!" set against KNOWN_OUTSIDE.  Empty array => rc=0.
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
    if (!found.has(site)) v.push("expected site migrated/removed (refresh allowlist): " + site);
  }
  return v;
}

// Compare the found KE text-sniff set against KNOWN_TEXT_SNIFF.  Empty array
// => rc=0 on the current tree; P3.3b shrinks the allowlist to zero.
function textSniffViolations(sites: string[]): string[] {
  const v: string[] = [];
  const known = new Set(KNOWN_TEXT_SNIFF);
  const found = new Set(sites);
  for (const site of found) {
    if (!known.has(site)) v.push("new text-sniff outside allowlist: " + site);
  }
  for (const site of known) {
    if (!found.has(site)) v.push("expected text-sniff migrated/removed (refresh allowlist): " + site);
  }
  return v;
}

test("P3.3 guard: current tree has no outside-coerce bypass (rc=0)", () => {
  const sources = readSources();
  const sites = outsideCoerceSites(sources);
  const v = violations(sites, coerceDeclarationCount(sources));
  expect(
    v,
    "guard must report zero violations on the current tree\n" + v.join("\n"),
  ).toEqual([]);
});

test('P3.3 guard: injecting one fresh postfix +"!!" bypass is caught (rc!=0)', () => {
  const sources = readSources();
  const exprLines = sources["KotlinExpr.hx"];
  const injectedLine = exprLines.length + 1;
  const modified: Sources = {
    ...sources,
    "KotlinExpr.hx": [
      ...exprLines,
      'class GuardInjectedBypass { static function emit(value:String):String return value + "!!"; }',
    ],
  };
  const sites = outsideCoerceSites(modified);
  const v = violations(sites, coerceDeclarationCount(modified));
  expect(v).toEqual(["new bypass outside coerce: KotlinExpr.hx:" + injectedLine]);
});

test("P3.3 guard: current tree has zero KE text-sniffs (rc=0)", () => {
  const sources = readSources();
  const sites = textSniffSites(sources);
  const v = textSniffViolations(sites);
  expect(
    v,
    "guard must report zero text-sniff violations on the current tree\n" + v.join("\n"),
  ).toEqual([]);
});

test("P3.3 guard: injecting one fresh KE text-sniff is caught (rc!=0)", () => {
  const sources = readSources();
  const exprLines = sources["KotlinExpr.hx"];
  const injectedLine = exprLines.length + 1;
  const modified: Sources = {
    ...sources,
    "KotlinExpr.hx": [
      ...exprLines,
      'final injectedSniff = rendered.indexOf("?.") >= 0;',
    ],
  };
  const sites = textSniffSites(modified);
  const v = textSniffViolations(sites);
  expect(v).toEqual(["new text-sniff outside allowlist: KotlinExpr.hx:" + injectedLine]);
});
