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

function markdownFiles(): string[] {
  if (!existsSync(DOCS)) return [];
  return readdirSync(DOCS)
    .filter((f) => f.endsWith(".md"))
    .map((f) => join(DOCS, f));
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
  test("the documents directory is present and non-empty", () => {
    const files = markdownFiles();
    expect(files.length, `no markdown found under ${DOCS}; discovery is broken`).toBeGreaterThan(0);
  });

  test("every cited object hash resolves in this repository or names its own", () => {
    const unresolvable: string[] = [];
    let checked = 0;

    for (const file of markdownFiles()) {
      const text = readFileSync(file, "utf8");
      const lines = text.split("\n");
      for (const [i, line] of lines.entries()) {
        if (FOREIGN_REPO_MARKERS.some((m) => line.includes(m))) continue;
        for (const m of line.matchAll(HASH_REF)) {
          const ref = m[1]!;
          checked += 1;
          if (objectType(ref) === null) {
            unresolvable.push(`${file.replace(`${REPO_ROOT}/`, "")}:${i + 1} cites \`${ref}\`, which does not resolve`);
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
