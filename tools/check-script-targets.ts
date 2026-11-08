// GATE-GUARD static check (A): every file target referenced by a package.json
// script must exist. This is the layer that catches "the script still runs but
// its entry file was deleted by a merge" — a gutted script cannot check itself,
// so this check lives OUTSIDE the scripts it guards.
//
// Scope rules:
//   - A token is treated as a file target if it ends in a known file
//     extension (.ts .js .mjs .cjs .sh .hxml), does not start with "-" (flag),
//     and contains no variable expansion ($ or %) or assignment (=).
//   - Generated output is skipped: paths under out/ and reference/*/gen/
//     are build products (git-ignored) produced at runtime; their absence
//     at rest is not a defect and would be a false positive.
//
// Exit codes: 0 all referenced targets exist; 1 at least one is missing;
// 2 usage/config error (package.json unreadable).

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const TARGET_EXTENSIONS = [".ts", ".js", ".mjs", ".cjs", ".sh", ".hxml"];

const repoRoot = join(import.meta.dir, "..");
const pkgPath = join(repoRoot, "package.json");

let scripts: Record<string, string>;
try {
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as { scripts?: Record<string, string> };
  scripts = pkg.scripts ?? {};
} catch (error) {
  console.error("check-script-targets: cannot read package.json: " + error);
  process.exit(2);
}

const missing: { script: string; target: string }[] = [];
const checked: { script: string; target: string }[] = [];

for (const [name, command] of Object.entries(scripts)) {
  for (const token of command.split(/\s+/)) {
    if (token.length === 0) continue;
    if (token.startsWith("-")) continue; // flag or flag value marker
    if (token.includes("=") || token.includes("$") || token.includes("%")) continue; // dynamic
    if (token.startsWith("out/")) continue; // generated build output
    if (/^reference\/[^/]+\/gen\//.test(token)) continue; // generated reference runner
    if (!TARGET_EXTENSIONS.some((ext) => token.endsWith(ext))) continue;
    const target = join(repoRoot, token);
    checked.push({ script: name, target: token });
    if (!existsSync(target)) missing.push({ script: name, target: token });
  }
}

if (missing.length > 0) {
  console.error("check-script-targets: FAIL — package.json scripts reference missing files:");
  for (const m of missing) console.error("  MISSING " + m.target + "  (script: " + m.script + ")");
  process.exit(1);
}
console.log("check-script-targets: PASS — " + checked.length + " file targets referenced by " + Object.keys(scripts).length + " scripts, all present");
process.exit(0);
