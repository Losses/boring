#!/usr/bin/env bun
// emit-invariant-check.ts
// Verify the emit-origin invariant on generated target code.
//
// Every conversion token in the generated tree must be accounted for by a
// coerce/refer event recorded in the matching .emit-origin.json sidecar:
//   Kotlin: "!!" and "== true"
//   Swift:  postfix "!"
//   Rust:   ".unwrap()"
//
// Direction 1 (default): scan a generated tree and exit 0 when every token
//   is accounted for, 1 otherwise.
// Direction 2 (probe): when the Kotlin build ran with
//   -D kotlin_coerce_bypass_probe, the compiler injects one "!!" OUTSIDE
//   coerce. The checker flags it and prints file:line:col plus the emission
//   call stack, then exits 1.
//
// Usage:
//   bun tools/emit-invariant-check.ts <gen-dir> [--lang kotlin|swift|rust]

import fs from "node:fs";
import path from "node:path";

type Lang = "kotlin" | "swift" | "rust";

interface Token {
  line: number;
  col: number;
  kind: string;
}

interface CoerceEvent {
  line: number;
  column: number;
  role: string;
  presence: string;
  admitsAbsence: boolean;
  sourceFile: string;
  operation: string;
  genLine: number;
  genColumn: number;
}

interface ReferEvent {
  line: number;
  column: number;
  sourceFile: string;
}

interface CallStackFrame {
  name: string;
  line: number;
  column: number;
  file: string;
}

interface Sidecar {
  v: number;
  sourceFiles: string[];
  frames: string[];
  lines: unknown[];
  coerceEvents: CoerceEvent[];
  referEvents: ReferEvent[];
  callStackFrames: CallStackFrame[];
}

interface LineEntry {
  frameId: number;
  sourceFileId: number;
  sourceLine: number;
  sourceColumn: number;
  callStack: number[];
  origin: string;
  inheritedFrom: number;
}

const NEWLINE = 10;
const BACKSLASH = 92;
const SPACE = 32;
const TAB = 9;

function isIdentChar(c: string): boolean {
  const code = c.charCodeAt(0);
  return (code >= 97 && code <= 122) || (code >= 65 && code <= 90) ||
    (code >= 48 && code <= 57) || code === 95;
}

function scanTokens(content: string, lang: Lang): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  let line = 1;
  let col = 1;
  const n = content.length;

  while (i < n) {
    const c = content[i];
    const nxt = i + 1 < n ? content[i + 1] : "";

    // line comment
    if (c === "/" && nxt === "/") {
      while (i < n && content.charCodeAt(i) !== NEWLINE) { i++; col++; }
      continue;
    }

    // block comment (nested, as in Kotlin/Swift/Rust)
    if (c === "/" && nxt === "*") {
      let depth = 1;
      i += 2; col += 2;
      while (i < n && depth > 0) {
        const a = content[i];
        const b = i + 1 < n ? content[i + 1] : "";
        if (a === "/" && b === "*") { depth++; i += 2; col += 2; }
        else if (a === "*" && b === "/") { depth--; i += 2; col += 2; }
        else if (content.charCodeAt(i) === NEWLINE) { i++; line++; col = 1; }
        else { i++; col++; }
      }
      continue;
    }

    // string / raw string
    if (c === '"') {
      if (content[i + 1] === '"' && content[i + 2] === '"') {
        i += 3; col += 3;
        while (i < n && !(content[i] === '"' && content[i + 1] === '"' && content[i + 2] === '"')) {
          if (content.charCodeAt(i) === NEWLINE) { i++; line++; col = 1; }
          else { i++; col++; }
        }
        i += 3; col += 3;
        continue;
      }
      i++; col++;
      while (i < n) {
        const ch = content.charCodeAt(i);
        if (ch === BACKSLASH) { i += 2; col += 2; continue; }
        if (content[i] === '"') { i++; col++; break; }
        if (ch === NEWLINE) { i++; line++; col = 1; }
        else { i++; col++; }
      }
      continue;
    }

    // char literal
    if (c === "'") {
      i++; col++;
      while (i < n) {
        const ch = content.charCodeAt(i);
        if (ch === BACKSLASH) { i += 2; col += 2; continue; }
        if (content[i] === "'") { i++; col++; break; }
        if (ch === NEWLINE) { i++; line++; col = 1; }
        else { i++; col++; }
      }
      continue;
    }

    // ---- Kotlin tokens ----
    if (lang === "kotlin") {
      if (c === "!" && nxt === "!") {
        tokens.push({ line: line, col: col, kind: "!!" });
        i += 2; col += 2;
        continue;
      }
      if (c === "=" && nxt === "=") {
        let k = i + 2;
        while (k < n && (content.charCodeAt(k) === SPACE || content.charCodeAt(k) === TAB)) { k++; }
        if (k + 4 <= n && content.slice(k, k + 4) === "true") {
          const after = content.charAt(k + 4);
          if (after === "" || !isIdentChar(after)) {
            tokens.push({ line: line, col: col, kind: "== true" });
            col += (k + 4) - i;
            i = k + 4;
            continue;
          }
        }
      }
    }

    // ---- Swift token: postfix force-unwrap ----
    if (lang === "swift") {
      if (c === "!" && nxt !== "=" && isPostfixContext(content, i)) {
        tokens.push({ line: line, col: col, kind: "!" });
        i++; col++;
        continue;
      }
    }

    // ---- Rust token: .unwrap() ----
    if (lang === "rust") {
      if (c === "." && content.slice(i + 1, i + 7) === "unwrap" && content[i + 7] === "(") {
        tokens.push({ line: line, col: col, kind: ".unwrap()" });
        i += 8; col += 8;
        continue;
      }
    }

    if (content.charCodeAt(i) === NEWLINE) { i++; line++; col = 1; }
    else { i++; col++; }
  }

  return tokens;
}

function isPostfixContext(content: string, i: number): boolean {
  let j = i - 1;
  while (j >= 0) {
    const ch = content.charCodeAt(j);
    if (ch !== SPACE && ch !== TAB && ch !== NEWLINE) break;
    j--;
  }
  if (j < 0) return false;
  const p = content.charAt(j);
  return isIdentChar(p) || p === ")" || p === "]" || p === "}" || p === "." ||
    p === '"' || p === "'" || p === ">";
}

function readSidecar(p: string): Sidecar | null {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8")) as Sidecar;
  } catch {
    return null;
  }
}

function lineEntry(sidecar: Sidecar, line1: number): LineEntry | null {
  const entry = sidecar.lines[line1 - 1];
  if (!Array.isArray(entry)) return null;
  const e = entry as unknown[];
  if (typeof e[0] !== "number") return null;
  if (e.length >= 8) {
    return {
      frameId: e[0] as number,
      sourceFileId: typeof e[1] === "number" ? (e[1] as number) : -1,
      sourceLine: typeof e[4] === "number" ? (e[4] as number) : -1,
      sourceColumn: typeof e[5] === "number" ? (e[5] as number) : -1,
      callStack: Array.isArray(e[6]) ? (e[6] as number[]) : [],
      origin: typeof e[7] === "string" ? (e[7] as string) : "",
      inheritedFrom: typeof e[8] === "number" ? (e[8] as number) : -1,
    };
  }
  // short legacy form: [frameId]
  return {
    frameId: e[0] as number,
    sourceFileId: -1,
    sourceLine: -1,
    sourceColumn: -1,
    callStack: [],
    origin: "",
    inheritedFrom: -1,
  };
}

function frameName(sidecar: Sidecar, frameId: number): string {
  if (frameId >= 0 && sidecar.frames && sidecar.frames[frameId]) return sidecar.frames[frameId];
  return "";
}

// Correlation is by generated position: every conversion CoerceEvent now
// carries genLine/genColumn (P7.2 EmitSink fix), so a token matches the event
// emitted for that same generated token. The bypass probe (direction 2) is
// recorded via record(), not recordCoerce(), so it has no event and is
// flagged here with its emission call stack.
function findMatchingEvent(sidecar: Sidecar, token: Token, entry: LineEntry | null, lang: Lang): CoerceEvent | ReferEvent | null {
  if (lang === "kotlin") {
    for (const ev of sidecar.coerceEvents || []) {
      if (ev.operation !== token.kind) continue;
      if (ev.genLine === token.line) return ev;
    }
    return null;
  }
  if (lang === "rust") {
    if (!entry) return null;
    for (const ev of sidecar.referEvents || []) {
      if (entry.sourceLine >= 0 && ev.line === entry.sourceLine + 1) return ev;
    }
    return null;
  }
  if (lang === "swift") {
    for (const ev of sidecar.coerceEvents || []) {
      if (ev.genLine === token.line) return ev;
    }
    return null;
  }
  return null;
}

function walkFiles(dir: string, ext: string): string[] {
  const out: string[] = [];
  const stack: string[] = [dir];
  while (stack.length > 0) {
    const cur = stack.pop();
    if (cur === undefined) continue;
    let entries: string[];
    try { entries = fs.readdirSync(cur); } catch { continue; }
    for (const name of entries) {
      const full = path.join(cur, name);
      let st;
      try { st = fs.statSync(full); } catch { continue; }
      if (st.isDirectory()) stack.push(full);
      else if (st.isFile() && full.endsWith(ext)) out.push(full);
    }
  }
  out.sort();
  return out;
}

function reportViolation(rel: string, t: Token, sidecar: Sidecar | null, entry: LineEntry | null, reason: string): void {
  console.log(rel + ":" + t.line + ":" + t.col + "  " + t.kind + "  ->  " + reason);
  if (entry && sidecar && entry.callStack.length > 0 && Array.isArray(sidecar.callStackFrames)) {
    const cs = entry.callStack;
    console.log("    emission call stack (" + cs.length + " frame(s), innermost first):");
    const limit = Math.min(cs.length, 16);
    for (let d = 0; d < limit; d++) {
      const fid = cs[d];
      if (typeof fid === "number" && fid >= 0 && sidecar.callStackFrames[fid]) {
        const fr = sidecar.callStackFrames[fid];
        const nm = fr.name || "<unknown>";
        const loc = fr.file ? (fr.file + ":" + fr.line + ":" + fr.column) : "<unknown>";
        console.log("      #" + d + "  " + nm + "  at  " + loc);
      }
    }
  } else {
    console.log("    (no emission call stack recorded for this line)");
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error("usage: bun tools/emit-invariant-check.ts <gen-dir> [--lang kotlin|swift|rust]");
    process.exit(2);
  }
  const genDir = args[0] as string;
  let lang: Lang = "kotlin";
  const li = args.indexOf("--lang");
  if (li >= 0 && args[li + 1]) {
    const v = args[li + 1];
    if (v === "kotlin" || v === "swift" || v === "rust") lang = v;
  }

  const abs = path.resolve(genDir);
  if (!fs.existsSync(abs)) {
    console.error("gen dir not found: " + abs);
    process.exit(2);
  }

  const ext = lang === "kotlin" ? ".kt" : lang === "swift" ? ".swift" : ".rs";
  const files = walkFiles(abs, ext);

  let tokensTotal = 0;
  let matched = 0;
  let violations = 0;

  for (const f of files) {
    const content = fs.readFileSync(f, "utf8");
    const tokens = scanTokens(content, lang);
    const sidecar = readSidecar(f + ".emit-origin.json");
    const rel = path.relative(process.cwd(), f);
    for (const t of tokens) {
      tokensTotal++;
      const entry = sidecar ? lineEntry(sidecar, t.line) : null;
      const frame = sidecar && entry ? frameName(sidecar, entry.frameId) : "";
      const ev = sidecar ? findMatchingEvent(sidecar, t, entry, lang) : null;
      if (ev) { matched++; continue; }
      violations++;
      const reason = frame === "BYPASS_PROBE"
        ? "bypass probe (kotlin_coerce_bypass_probe) - not emitted through coerce"
        : "no matching coerce/refer event";
      reportViolation(rel, t, sidecar, entry, reason);
    }
  }

  console.log("");
  console.log("emit-invariant-check: lang=" + lang + " files=" + files.length +
    " tokens=" + tokensTotal + " matched=" + matched + " violations=" + violations);
  if (violations > 0) {
    console.log("FAIL: " + violations + " conversion token(s) not accounted for by a coerce/refer event.");
    process.exit(1);
  }
  console.log("OK: every conversion token is accounted for.");
  process.exit(0);
}

await main();
