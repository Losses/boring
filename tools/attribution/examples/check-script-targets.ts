#!/usr/bin/env bun
// Repro command used by the historical drill. It checks that every file
// target named by package.json scripts exists in the current directory.
// The command runs from a candidate checkout, so it reports the missing
// target at that commit.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

type PackageFile = {
  scripts?: Record<string, string>;
};

const TARGET_EXTENSIONS = [".ts", ".js", ".mjs", ".cjs", ".sh", ".hxml"];
const root = process.cwd();
const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8")) as PackageFile;
const scripts = pkg.scripts ?? {};
const missing: string[] = [];
let checked = 0;
for (const name of Object.keys(scripts)) {
  const command = scripts[name];
  if (command === undefined) continue;
  for (const token of command.split(/\s+/)) {
    if (token.length === 0) continue;
    if (token.startsWith("-")) continue;
    if (token.includes("=") || token.includes("$") || token.includes("%")) continue;
    if (token.startsWith("out/")) continue;
    if (/^reference\/[^/]+\/gen\//.test(token)) continue;
    if (!TARGET_EXTENSIONS.some((extension) => token.endsWith(extension))) continue;
    checked += 1;
    if (!existsSync(join(root, token))) missing.push(token + " (script " + name + ")");
  }
}
if (missing.length > 0) {
  for (const target of missing) console.error("MISSING " + target);
  console.error("script-targets: FAIL (" + String(missing.length) + " missing of " + String(checked) + " targets)");
  process.exit(1);
}
console.log("script-targets: PASS (" + String(checked) + " targets)");
process.exit(0);
