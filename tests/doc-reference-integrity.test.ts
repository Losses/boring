import { describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Reference integrity for the architecture documents.
 *
 * The documents cite their evidence two ways, and only one of them survives:
 *
 *   * a **commit hash** persists -- `git cat-file` resolves it forever;
 *   * a **worktree name** does not -- worktrees are cleaned up, cleanup leaves
 *     no trace, and the citation keeps reading as checkable afterwards.
 *
 * Three `out/...` worktree names in these documents were found dead on
 * 2026-10-01 while every commit hash cited beside them resolved. So the
 * checkable half is mechanised here: every hash-like backtick reference must
 * resolve to a real object in this repository -- unless the citing line says
 * which OTHER repository it belongs to.
 *
 * What this deliberately does NOT check:
 *   * worktree names -- they are gone by design, and a guard cannot verify a
 *     path that no longer exists without asserting the absence is a defect,
 *     which it is not;
 *   * whether the cited object is the RIGHT one. This checks reachability, not
 *     correctness. A citation can resolve and still point at the wrong commit.
 */

const REPO_ROOT = resolve(import.meta.dir, "..");
const DOCS = join(REPO_ROOT, "docs", "architecture");

/** Backticked hex that looks like a bare object id, not a URL fragment or a
    byte count. 7 hex chars is git's shortest unambiguous abbreviation. */
const HASH_REF = /`([0-9a-f]{7,40})`/g;

/** Lines that name another repository make the hash legitimately foreign. The
    phrasing is matched rather than the hash, because the point is that the
    AUTHOR said where it lives -- not that we guessed. */
const FOREIGN_REPO_MARKERS = [
  "Tiqian repository",
  "Tiqian 仓库",
  "not this one",
  "另一个仓库",
  "外部仓库",
];

/** A hash-notation value that is NOT an object id -- an uncommitted diff state,
    for instance. Found 2026-10-01: four `tracked diff <hash>` citations in
    compiler-policy-interfaces.md can never resolve, because an uncommitted diff
    has no object id. That is a NOTATION problem, not staleness, and the failure
    looks identical to a cleaned-up reference from the reader's side. So the
    citing line must say which kind it is; the words are matched, not the value. */
const NON_OBJECT_MARKERS = [
  "tracked diff",
  "未提交",
  "uncommitted",
  "不是对象 id",
];

function markdownFiles(): string[] {
  // Two locations, not one. The guard originally scanned only
  // docs/architecture/ and therefore missed docs/architecture-work-plan.md and
  // docs/compiler-policy-interfaces.md -- which is where the four unresolvable
  // diff citations were living. A guard whose observation domain is smaller than
  // the property it claims to protect is the failure this file exists to catch,
  // so the domain is stated here and asserted below.
  const dirs = [DOCS, join(REPO_ROOT, "docs")];
  const out: string[] = [];
  for (const dir of dirs) {
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir)) {
      if (f.endsWith(".md")) out.push(join(dir, f));
    }
  }
  return out;
}

function objectType(ref: string): string | null {
  try {
    return execFileSync("git", ["cat-file", "-t", ref], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

describe("architecture document reference integrity", () => {
  test("the document set is discovered from more than one directory", () => {
    const files = markdownFiles();
    expect(files.length, `no markdown found; discovery is broken`).toBeGreaterThan(0);
    const outside = files.filter((f) => !f.startsWith(`${DOCS}/`));
    expect(
      outside.length,
      "the scan found only docs/architecture/; the domain has silently narrowed, " +
        "which is how the four tracked-diff citations went unchecked",
    ).toBeGreaterThan(0);
  });

  test("every cited object hash resolves, or its line says why it cannot", () => {
    const unresolvable: string[] = [];
    let checked = 0;

    for (const file of markdownFiles()) {
      const text = readFileSync(file, "utf8");
      const lines = text.split("\n");
      for (const [i, line] of lines.entries()) {
        // A hash may legitimately not resolve when the line names another
        // repository, or when it says the value is not an object id at all
        // (an uncommitted diff). Both are the AUTHOR stating which kind it is.
        if (FOREIGN_REPO_MARKERS.some((m) => line.includes(m))) continue;
        if (NON_OBJECT_MARKERS.some((m) => line.includes(m))) continue;
        for (const m of line.matchAll(HASH_REF)) {
          const ref = m[1]!;
          checked += 1;
          if (objectType(ref) === null) {
            unresolvable.push(
              `${file.replace(`${REPO_ROOT}/`, "")}:${i + 1} cites \`${ref}\`, which does not resolve — ` +
                `fix the hash, or say which repository it lives in, or mark it as not an object id`,
            );
          }
        }
      }
    }

    // A guard whose observation domain is empty passes without checking
    // anything, which is worse than failing. 94 references existed when this
    // was written; require a substantial fraction so a regex break is loud.
    expect(checked, "no object references were found; the scan is not matching").toBeGreaterThan(20);

    expect(
      unresolvable,
      `cited objects that do not resolve — either fix the hash, or say which repository it lives in:\n  ${unresolvable.join("\n  ")}`,
    ).toEqual([]);
  });
});
