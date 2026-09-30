// GATE-LEDGER.md entry-gate R2/R3 evidence producer.
//
// Given a commit-ish, exports the commit's tree with `git archive` into a
// temporary directory, re-hashes every file the tree records with
// `git hash-object`, and compares against `git ls-tree -r`. The verdict comes
// ONLY from that comparison, never from `git archive` succeeding.
//
// Read-only with respect to the repository: the live worktree is never touched
// and no object is ever written (`git hash-object` is used without `-w`), so
// the proof does not require a clean live worktree — it cannot even see one.
//
// Usage:
//   bun tools/gate-proof/verify-commit.ts <commit-ish>                 export + verify
//   bun tools/gate-proof/verify-commit.ts <commit-ish> --verify-export <dir>
//       skip git archive and verify an already-exported directory (e.g. a
//       freeze archive) against the commit's recorded tree instead.
//   --json <path>   additionally write the machine-readable summary there.
//
// Exit codes: 0 all files match; 1 mismatch/error; 2 usage error.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const fail = (message: string): never => {
  console.error(`gate-proof: ${message}`);
  process.exit(1);
};

const git = (args: string[]): string =>
  execFileSync("git", args, { maxBuffer: 1 << 28 }).toString();

const args = process.argv.slice(2);
const jsonPathIndex = args.indexOf("--json");
let jsonPath: string | undefined;
if (jsonPathIndex !== -1) {
  jsonPath = args[jsonPathIndex + 1];
  if (!jsonPath) fail("--json requires a path");
  args.splice(jsonPathIndex, 2);
}
const verifyExportIndex = args.indexOf("--verify-export");
let verifyExportDir: string | undefined;
if (verifyExportIndex !== -1) {
  verifyExportDir = args[verifyExportIndex + 1];
  if (!verifyExportDir) fail("--verify-export requires a directory");
  args.splice(verifyExportIndex, 2);
}
if (args.length !== 1) {
  console.error("usage: bun tools/gate-proof/verify-commit.ts <commit-ish> [--verify-export <dir>] [--json <path>]");
  process.exit(2);
}
const commitish = args[0]!;

// R1 pre-condition: the argument must resolve to a commit. A blob, tree or
// tag object or a nonexistent name fails here with a clear message.
let commit: string;
try {
  commit = git(["rev-parse", "--verify", "--quiet", `${commitish}^{commit}`]).trim();
} catch {
  fail(`'${commitish}' does not resolve to a commit object (nonexistent hash, or a blob/tree/tag was given)`);
}
const tree = git(["rev-parse", "--verify", "--quiet", `${commit}^{tree}`]).trim();

// Recorded side of the comparison: every path the tree carries, with its blob.
const lsTree = git(["ls-tree", "-r", "-z", commit]);
const expected = new Map<string, string>();
for (const entry of lsTree.split("\0")) {
  if (entry.length === 0) continue;
  const meta = entry.split("\t");
  const info = meta[0]!.split(/\s+/);
  if (info[1] !== "blob") fail(`unexpected non-blob entry in tree of ${commit}: ${entry}`);
  expected.set(meta[1]!, info[2]!);
}

// Export side. Default: git archive into a throwaway temp directory.
// --verify-export: an independently produced export (the R3 freeze-archive
// case); it must exist and be a directory, and every path below is checked.
let exportDir: string;
let madeTemp = false;
if (verifyExportDir !== undefined) {
  exportDir = resolve(verifyExportDir);
  if (!existsSync(exportDir) || !statSync(exportDir).isDirectory()) {
    fail(`--verify-export '${exportDir}' is not an existing directory`);
  }
} else {
  exportDir = mkdtempSync(join(tmpdir(), "gate-proof-"));
  madeTemp = true;
  try {
    // Extract into exportDir ourselves so a failed archive cannot be mistaken
    // for a verified export: the verdict below only counts hashed comparisons.
    const tar = execFileSync("git", ["archive", "--format=tar", commit], { maxBuffer: 1 << 28 });
    execFileSync("tar", ["-x", "-C", exportDir], { input: tar });
  } catch {
    rmSync(exportDir, { recursive: true, force: true });
    fail(`git archive/tar extraction failed for ${commit}`);
  }
}

// The comparison IS the verdict. Every recorded path must exist in the export
// and re-hash to exactly the recorded blob oid.
const mismatches: { path: string; reason: string }[] = [];
const hashed: string[] = [];
for (const [path, oid] of [...expected.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
  const file = join(exportDir, path);
  if (!existsSync(file)) {
    mismatches.push({ path, reason: "missing from export" });
    continue;
  }
  let actual: string;
  try {
    actual = execFileSync("git", ["hash-object", "--", file], { maxBuffer: 1 << 24 }).toString().trim();
  } catch (error) {
    mismatches.push({ path, reason: `hash-object failed: ${error}` });
    continue;
  }
  hashed.push(path);
  if (actual !== oid) mismatches.push({ path, reason: `blob mismatch: recorded ${oid}, export hashes ${actual}` });
}
// And nothing extra may hide in the export either (only meaningful for a
// provided directory; a fresh git archive cannot contain extras).
if (verifyExportDir !== undefined) {
  const walk = (dir: string, prefix: string): void => {
    for (const name of readdirSync(dir, { withFileTypes: true })) {
      const path = prefix === "" ? name.name : `${prefix}/${name.name}`;
      if (name.isDirectory()) walk(join(dir, name.name), path);
      else if (name.isFile() && !expected.has(path)) mismatches.push({ path, reason: "present in export but not in commit tree" });
    }
  };
  walk(exportDir, "");
}

const fileList = [...expected.keys()].sort();
const listSha256 = createHash("sha256").update(fileList.join("\n") + (fileList.length ? "\n" : "")).digest("hex");
const pass = mismatches.length === 0;

const summary = {
  tool: "tools/gate-proof/verify-commit.ts",
  commit,
  tree,
  commitish,
  mode: verifyExportDir !== undefined ? "verify-export" : "archive-verify",
  exportDir: madeTemp ? "(temporary, removed)" : exportDir,
  totalFiles: expected.size,
  hashedFiles: hashed.length,
  mismatches: mismatches.length,
  mismatchedPaths: mismatches,
  fileListSha256: listSha256,
  verdict: pass ? "PASS" : "FAIL",
};

const lines: string[] = [
  `commit:        ${commit}`,
  `tree:          ${tree}`,
  `mode:          ${summary.mode}`,
  `total files:   ${expected.size}`,
  `hashed:        ${hashed.length}`,
  `mismatches:    ${mismatches.length}`,
  `file-list sha256: ${listSha256}`,
  `verdict:       ${pass ? "PASS" : "FAIL"}`,
];
for (const m of mismatches.slice(0, 50)) lines.push(`  MISMATCH ${m.path}: ${m.reason}`);
if (mismatches.length > 50) lines.push(`  ... and ${mismatches.length - 50} more`);
console.log(lines.join("\n"));

if (jsonPath !== undefined) writeFileSync(jsonPath, JSON.stringify(summary, null, 2) + "\n");

if (madeTemp) rmSync(exportDir, { recursive: true, force: true });
process.exit(pass ? 0 : 1);
