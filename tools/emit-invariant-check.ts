// tools/emit-invariant-check.ts
// Emission-invariant checker (P7.2 / P7.3).
//
// P7.3 adds two checks:
//   1. ReferEvent must be resolved=true, PLUS an independent Rust-artifact
//      cross-check: parse lib.rs + every mod.rs to build the module tree and
//      verify each use crate::... path resolves.
//   2. CoerceEvent must not contain (MaybeAbsent, admitsAbsence=false,
//      operation=null).
//
// P7.2 appends its own check as another pure function returning Violation[]
// registered in main(). Keep each check additive and side-effect-free.
//
// Usage: bun tools/emit-invariant-check.ts <output-dir> [...]
// Exit 0 when clean, 1 when violations are found, 2 on usage errors.

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, relative, basename } from "node:path";

type Violation = { check: string; message: string };

function walkFiles(dir: string): string[] {
  const out: string[] = [];
  function rec(d: string): void {
    let entries: string[];
    try {
      entries = readdirSync(d);
    } catch {
      return;
    }
    for (const e of entries) {
      const p = join(d, e);
      let st;
      try {
        st = statSync(p);
      } catch {
        continue;
      }
      if (st.isDirectory()) rec(p);
      else out.push(p);
    }
  }
  rec(dir);
  return out;
}

function readJson(path: string): any | null {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Check 1a: every ReferEvent must be resolved === true.
// ---------------------------------------------------------------------------
function checkReferResolved(dir: string): Violation[] {
  const out: Violation[] = [];
  const refPath = join(dir, "refer.emit-origin.json");
  if (!existsSync(refPath)) return out;
  const json = readJson(refPath);
  if (!json || !Array.isArray(json.referEvents)) return out;
  for (const ev of json.referEvents) {
    if (ev.resolved !== true) {
      const symbol = ev.symbol ?? "?";
      const fromUnit = ev.fromUnit ?? "?";
      out.push({
        check: "refer-resolved",
        message:
          "ReferEvent unresolved: symbol=" + symbol +
          " fromUnit=" + fromUnit + " resolved=" + ev.resolved,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Check 1b: independent Rust module-tree cross-check.
// Build the module tree from lib.rs + every mod.rs, then verify each
// use crate::... path's module prefix resolves.
// ---------------------------------------------------------------------------
function extractModDecls(src: string): string[] {
  const names: string[] = [];
  for (const line of src.split("\n")) {
    const m = line.match(/^\s*(?:pub\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*;/);
    if (m) names.push(m[1]);
  }
  return names;
}

function buildModuleTree(dir: string): Set<string> | null {
  const libPath = join(dir, "lib.rs");
  if (!existsSync(libPath)) return null;
  const modules = new Set<string>();
  function visit(idPath: string[], fsDir: string, declFile: string): void {
    let src: string;
    try {
      src = readFileSync(declFile, "utf8");
    } catch {
      return;
    }
    for (const name of extractModDecls(src)) {
      const childId = idPath.concat([name]);
      const childIdStr = childId.join("::");
      modules.add(childIdStr);
      const dirMod = join(dir, fsDir, name, "mod.rs");
      const leaf = join(dir, fsDir, name + ".rs");
      if (existsSync(dirMod)) {
        visit(childId, join(fsDir, name), dirMod);
      } else if (existsSync(leaf)) {
        // leaf module: no further nesting to descend
      }
      // else: declared but file missing; the use-path check below still
      // catches any use crate::... pointing at it.
    }
  }
  visit([], "", libPath);
  return modules;
}

function checkRustUsePaths(dir: string, modules: Set<string>): Violation[] {
  const out: Violation[] = [];
  for (const file of walkFiles(dir)) {
    if (!file.endsWith(".rs")) continue;
    let src: string;
    try {
      src = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    const rel = relative(dir, file);
    const lines = src.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!line.includes("use crate::")) continue;
      const m = line.match(/use\s+crate::([^;]+);/);
      if (!m) continue;
      let path = m[1].trim();
      path = path.replace(/\s+as\s+[A-Za-z_][A-Za-z0-9_]*\s*$/, "");
      path = path.replace(/::\*$/, "");
      path = path.replace(/::\{[^}]*\}$/, "");
      const segments = path
        .split("::")
        .map((s: string) => s.trim())
        .filter((s: string) => s.length > 0);
      // Single-segment use crate::X; imports a root item/module; keep it
      // lenient to avoid false positives (items are not tracked here).
      if (segments.length <= 1) continue;
      const modulePart = segments.slice(0, -1);
      const current: string[] = [];
      let broken: string | null = null;
      for (const seg of modulePart) {
        current.push(seg);
        if (!modules.has(current.join("::"))) {
          broken = seg;
          break;
        }
      }
      if (broken !== null) {
        out.push({
          check: "rust-module-tree",
          message:
            "crate path broken at segment '" + broken +
            "' (module '" + modulePart.join("::") +
            "' not declared in lib.rs/mod.rs tree): " + line.trim() +
            " at " + rel + ":" + (i + 1),
        });
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Check 2: CoerceEvent must not be (MaybeAbsent, admitsAbsence=false,
// operation=null).
// ---------------------------------------------------------------------------
function checkCoerceCombo(dir: string): Violation[] {
  const out: Violation[] = [];
  const seen = new Set<string>();
  for (const file of walkFiles(dir)) {
    if (!file.endsWith(".emit-origin.json")) continue;
    if (basename(file) === "refer.emit-origin.json") continue;
    const json = readJson(file);
    if (!json || !Array.isArray(json.coerceEvents)) continue;
    for (const ev of json.coerceEvents) {
      if (
        ev.presence === "MaybeAbsent" &&
        ev.admitsAbsence === false &&
        (ev.operation === null || ev.operation === undefined)
      ) {
        const key =
          (ev.sourceFile ?? "?") + ":" + ev.line + ":" + ev.column + ":" + (ev.role ?? "?");
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({
          check: "coerce-combo",
          message:
            "illegal CoerceEvent (MaybeAbsent + admitsAbsence=false + operation=null) role=" +
            (ev.role ?? "?") + " at " + (ev.sourceFile ?? "?") + ":" + ev.line + ":" + ev.column,
        });
      }
    }
  }
  return out;
}

function main(): void {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error("usage: emit-invariant-check.ts <output-dir> [...]");
    process.exit(2);
  }
  const all: Violation[] = [];
  for (const dir of args) {
    if (!existsSync(dir)) {
      console.error("not found: " + dir);
      process.exit(2);
    }
    all.push(...checkReferResolved(dir));
    const modules = buildModuleTree(dir);
    if (modules !== null) {
      all.push(...checkRustUsePaths(dir, modules));
    }
    all.push(...checkCoerceCombo(dir));
  }
  if (all.length === 0) {
    console.log("OK: no invariant violations");
    process.exit(0);
  }
  for (const v of all) {
    console.log("VIOLATION[" + v.check + "]: " + v.message);
  }
  console.log(all.length + " violation(s)");
  process.exit(1);
}

main();
