import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

/**
 * P5.6 Swift I2 guard.
 *
 * SwiftCoerce.coerce is the single sanctioned emission point for the postfix
 * force-unwrap x + "!" and the nil-coalescing + " ?? ".  Any suffix + "!"
 * or + " ?? " emitted by files other than SwiftCoerce.hx is a conversion
 * bypass that the guard must report.
 *
 * Swift ! is also a prefix logical-NOT operator, which is emitted as
 * "!" + x.  The guard counts only the SUFFIX x + "!" form (the regex
 * requires + BEFORE the literal), so "!" + x is never flagged.
 *
 * The guard text-scans every swiftcompiler .hx file outside SwiftCoerce.hx
 * and collects each postfix-! and nil-coalescing emission line.  A site is
 * identified by its file name and its trimmed source text, counted as a
 * multiset.  Adding or removing unrelated lines above a site moves its line
 * number while its text identity stays the same, so the guard reports no
 * violation.  A fresh bypass, an edited emission line, or a dropped site
 * changes the multiset and reports a violation.
 *
 * Assertions:
 *   1. SwiftCoerce.hx contains exactly one "function coerce(" declaration,
 *      so renaming the sole entry point breaks the guard loudly.
 *   2. The found multiset matches KNOWN_OUTSIDE exactly (rc=0 on the current tree).
 *   3. Inserting blank lines above SwiftExpr.hx keeps the multiset unchanged
 *      (rc=0), so unrelated line movement reports no fresh bypass.
 *   4. Injecting one fresh + "!" bypass into the in-memory copy of
 *      SwiftExpr.hx produces exactly one violation (rc!=0), proving the
 *      guard is not vacuous.
 *   5. Appending a second copy of a sanctioned line raises that line's count
 *      and reports a fresh bypass, so repeated allowed text does not hide a site.
 *   6. Removing one occurrence of a line that the list carries twice reports
 *      migrated/removed, so the maintenance signal survives.
 */

const root = path.resolve(import.meta.dir, "../..");
const compilerDir = path.join(root, "packages/compiler/reflaxe/swift/swiftcompiler");
const COERCE_FILE = "SwiftCoerce.hx";

// A site is identified by file name plus trimmed source text.  The line
// number and the enclosing function are diagnostics only; neither takes part
// in the identity, so unrelated line movement cannot change a match.
type Anchored = {
  readonly file: string;
  readonly text: string;
};

type OutsideAnchor = Anchored;

type EmitSite = {
  readonly file: string;
  readonly line: number;
  readonly fn: string;
  readonly text: string;
};

/**
 * Sanctioned outside-coerce emission sites on the current tree, one entry per
 * matching line, in the format "File.hx :: <trimmed source text>".  The list
 * is a multiset: a line that occurs three times in a file appears three times
 * here.
 *
 * When a migration removes or rewrites a site, the guard reports
 * "expected site migrated/removed" and this list must be refreshed to the new
 * reality.  When a fresh bypass appears, the guard reports "new bypass
 * outside coerce".  An extra copy of a listed line raises that line's count
 * and reports as a fresh bypass, so repeating allowed text does not hide a
 * site.
 */
const KNOWN_OUTSIDE_TEXT = `
SwiftDecl.hx :: final typeText = nullInit && !StringTools.endsWith(declaredType, "?") ? declaredType + "!" : declaredType;
SwiftDecl.hx :: out.push("        " + keyword + " " + SwiftNameEscape.escape(a.name) + " = " + SwiftNameEscape.escape(a.name) + " ?? "
SwiftDecl.hx :: out.push("        " + keyword + " " + a.name + " = " + a.name + " ?? " + defaultText + ";");
SwiftExpr.hx :: text: valueText + " ?? " + coalescingDefaultText(value, site.valueExpr.t),
SwiftExpr.hx :: out.push(indent(depth + 1) + "let " + localName(gb.bucketVar) + " = " + expr(gb.getCall) + " ?? "
SwiftExpr.hx :: + " ?? "
SwiftExpr.hx :: case TLocal(_): t + "!";
SwiftExpr.hx :: return "(" + targetText + " ?? " + coalescingFallbackText(site.fallback, e.t) + ")";
SwiftExpr.hx :: return expr(getCall) + " ?? " + coalescingFallbackText(fallback, e.t);
SwiftExpr.hx :: final text = targetValue.optionality == SwiftArrayOptionality.RequiredOperand ? targetValue.text : targetValue.text + " ?? " + fallbackValue.text;
SwiftExpr.hx :: case TLocal(_): text + "!";
SwiftExpr.hx :: case TCall(_, _) if (isNullLeafType(ret.t)): currentFuncReturnsOptional ? expr(ret) : expr(ret) + "!";
SwiftExpr.hx :: case TLocal(v) if (swiftPresence(ret) != Present): expr(ret) + "!";
SwiftExpr.hx :: case _: currentFuncReturnsOptional ? expr(ret) : (swiftPresence(ret) != Present ? expr(ret) + "!" : expr(ret));
SwiftExpr.hx :: currentFuncReturnsOptional ? expr(ret) : (swiftPresence(ret) != Present ? expr(ret) + "!" : expr(ret));
SwiftExpr.hx :: return optional ? code : code + "!";
SwiftExpr.hx :: pt) : pt != null && !isNullLeafType(pt) && swiftPresence(a) != Present ? expr(a) + "!" : expr(a);
SwiftExpr.hx :: + " ?? "
SwiftExpr.hx :: "(" + expr(args[i]) + " ?? " + defaultArgText(d, p) + ")";
SwiftExpr.hx :: + " ?? "
SwiftExpr.hx :: "(" + expr(args[i]) + " ?? " + defaultArgText(d, p) + ")";
SwiftExpr.hx :: expr(args[i]) + "!";
SwiftExpr.hx :: final text = fieldType != null && !isNullLeafType(fieldType) && swiftPresence(value) != Present ? expr(value) + "!" : expr(value);
SwiftExpr.hx :: case _: optionalStringLeaf(leaf) ? expr(leaf) + "!" : expr(leaf);
`.trim();

const SITE_SEPARATOR = " :: ";

// Postfix force-unwrap: value + "!".  Requires + BEFORE the literal so the
// prefix logical-NOT form "!" + x is never matched.
const POSTFIX_BANG = /\+ *"!"/;

// Nil-coalescing emission: value + " ?? ".  Also requires + BEFORE so
// sniffers like lastIndexOf(" ?? ") (SwiftExpr.hx:2288) are excluded.
const COALESCE = /\+ *" *\? *\? *"/;

// A named function declaration starts an enclosing-function scope.  Anonymous
// functions (function(...) with no name) keep the surrounding named scope,
// which is enough for a diagnostic label.
const FUNCTION_DECL = /^\s*(?:public\s+|private\s+|static\s+|override\s+|inline\s+|extern\s+|final\s+)*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/;

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

function parseKnownOutside(): OutsideAnchor[] {
  const anchors: OutsideAnchor[] = [];
  for (const raw of KNOWN_OUTSIDE_TEXT.split("\n")) {
    const line = raw.trim();
    if (line.length === 0) continue;
    const separator = line.indexOf(SITE_SEPARATOR);
    if (separator < 0) {
      throw new Error("KNOWN_OUTSIDE entry lacks the separator: " + line);
    }
    anchors.push({
      file: line.slice(0, separator).trim(),
      text: line.slice(separator + SITE_SEPARATOR.length).trim(),
    });
  }
  return anchors;
}

// Collect every matching line in swiftcompiler *.hx outside SwiftCoerce.hx.
function collectSites(sources: Sources): EmitSite[] {
  const sites: EmitSite[] = [];
  for (const name of Object.keys(sources).sort()) {
    if (name === COERCE_FILE) continue;
    const lines = sources[name] ?? [];
    let fn = "(top-level)";
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index] ?? "";
      const declaration = FUNCTION_DECL.exec(line);
      if (declaration !== null) fn = declaration[1] ?? fn;
      if (POSTFIX_BANG.test(line) || COALESCE.test(line)) {
        sites.push({ file: name, line: index + 1, fn, text: line.trim() });
      }
    }
  }
  return sites;
}

function groupByAnchor<T extends Anchored>(entries: ReadonlyArray<T>): Map<string, T[]> {
  const groups = new Map<string, T[]>();
  for (const entry of entries) {
    const key = entry.file + "\n" + entry.text;
    const existing = groups.get(key);
    if (existing === undefined) groups.set(key, [entry]);
    else existing.push(entry);
  }
  return groups;
}

// Compare the found multiset against the allowlist multiset.  Returns an
// empty array when every count agrees (rc=0).
function violations(sites: ReadonlyArray<EmitSite>, coerceCount: number): string[] {
  const v: string[] = [];
  if (coerceCount !== 1) {
    v.push("coerce exists " + coerceCount + " time(s) in " + COERCE_FILE + " (expected exactly 1; rename breaks guard)");
  }
  const found = groupByAnchor(sites);
  const allowed = groupByAnchor(parseKnownOutside());
  for (const [key, siteGroup] of found) {
    const allowedGroup = allowed.get(key);
    const allowedCount = allowedGroup === undefined ? 0 : allowedGroup.length;
    for (let index = allowedCount; index < siteGroup.length; index += 1) {
      const site = siteGroup[index];
      if (site === undefined) continue;
      v.push("new bypass outside coerce: " + site.file + ":" + site.line + " (in " + site.fn + ") " + site.text);
    }
  }
  for (const [key, anchorGroup] of allowed) {
    const foundGroup = found.get(key);
    const foundCount = foundGroup === undefined ? 0 : foundGroup.length;
    for (let index = foundCount; index < anchorGroup.length; index += 1) {
      const anchor = anchorGroup[index];
      if (anchor === undefined) continue;
      v.push("expected site migrated/removed (refresh allowlist): " + anchor.file + " " + anchor.text);
    }
  }
  return v;
}

test("P5.6 guard: current tree has no outside-coerce bypass (rc=0)", () => {
  const sources = readSources();
  const v = violations(collectSites(sources), coerceDeclarationCount(sources));
  expect(v, "guard must report zero violations on the current tree\n" + v.join("\n")).toEqual([]);
});

test("P5.6 guard: blank lines above SwiftExpr.hx keep the guard green (rc=0)", () => {
  const sources = readSources();
  const blanks = Array.from({ length: 8 }, () => "");
  const drifted: Sources = {
    ...sources,
    "SwiftExpr.hx": [...blanks, ...(sources["SwiftExpr.hx"] ?? [])],
  };
  const v = violations(collectSites(drifted), coerceDeclarationCount(drifted));
  expect(v, "line drift must not report a bypass\n" + v.join("\n")).toEqual([]);
});

test('P5.6 guard: injecting one fresh postfix +"!" bypass is caught (rc!=0)', () => {
  const sources = readSources();
  const exprLines = sources["SwiftExpr.hx"] ?? [];
  const injectedLine = exprLines.length + 1;
  const injectedText = 'class GuardInjectedBypass { static function emit(value:String):String return value + "!"; }';
  const modified: Sources = {
    ...sources,
    "SwiftExpr.hx": [...exprLines, injectedText],
  };
  const v = violations(collectSites(modified), coerceDeclarationCount(modified));
  expect(v.length, "one fresh bypass must produce one violation:\n" + v.join("\n")).toBe(1);
  expect(v.some((entry) => entry.includes("new bypass outside coerce: SwiftExpr.hx:" + injectedLine))).toBe(true);
  expect(v.some((entry) => entry.includes(injectedText))).toBe(true);
});

test("P5.6 guard: every allowlisted site is recognised on the current tree", () => {
  const sources = readSources();
  const found = collectSites(sources);
  const anchors = parseKnownOutside();
  expect(found.length, "the found site count must equal the allowlist entry count").toBe(anchors.length);
  const foundKeys = [...groupByAnchor(found).keys()].sort();
  const anchorKeys = [...groupByAnchor(anchors).keys()].sort();
  expect(foundKeys).toEqual(anchorKeys);
});

test("P5.6 guard: a repeated sanctioned line raises its count and is caught (rc!=0)", () => {
  const sources = readSources();
  const anchors = parseKnownOutside();
  const repeated = anchors.find((anchor) => anchor.text.includes("defaultArgText(d, p)"));
  if (repeated === undefined) throw new Error("allowlist lost the defaultArgText anchor");
  const modified: Sources = {
    ...sources,
    [repeated.file]: [...(sources[repeated.file] ?? []), repeated.text],
  };
  const v = violations(collectSites(modified), coerceDeclarationCount(modified));
  expect(v.length, "a repeated allowed line must report one fresh bypass:\n" + v.join("\n")).toBe(1);
  expect(v.some((entry) => entry.includes("new bypass outside coerce: " + repeated.file))).toBe(true);
});

test("P5.6 guard: dropping one of two repeated sanctioned lines is reported (rc!=0)", () => {
  const sources = readSources();
  const anchors = parseKnownOutside();
  const repeated = anchors.find((anchor) => anchor.text === '+ " ?? "');
  if (repeated === undefined) throw new Error("allowlist lost the repeated coalesce anchor");
  const lines = sources[repeated.file] ?? [];
  const removeAt = lines.findIndex((line) => line.trim() === repeated.text);
  if (removeAt < 0) throw new Error("no source line matches the repeated coalesce anchor");
  const trimmed = [...lines.slice(0, removeAt), ...lines.slice(removeAt + 1)];
  const modified: Sources = { ...sources, [repeated.file]: trimmed };
  const v = violations(collectSites(modified), coerceDeclarationCount(modified));
  expect(v.length, "a dropped repeated line must report one migrated site:\n" + v.join("\n")).toBe(1);
  expect(v.some((entry) => entry.includes("expected site migrated/removed (refresh allowlist): " + repeated.file))).toBe(true);
});
