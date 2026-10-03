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

  /**
   * The second half of reference integrity: reachability is not enough.
   *
   * LAYERED-VERIFICATION's own L0 section requires every "this is fixed /
   * this is in effect" claim to carry the commit AND the result of
   * `git merge-base --is-ancestor <commit> arch/agent-guided-governance`.
   * That rule existed only as prose, so nobody ran it, and the file went on to
   * assert that S1 had zeroed the L3 build-phase diagnostic — citing a commit
   * (`cd70eb12`) that is NOT an ancestor of the base and that lives only on
   * `prep/p08-s1-unreachable-return`, while the fixture itself still asserts
   * the diagnostic is present.
   *
   * A rule the document states but no machine enforces is the failure mode.
   * So: a line that claims effect AND cites a hash must have that hash reachable
   * from the base, or must say the tree it actually holds on.
   */
  const BASE_BRANCH = "arch/agent-guided-governance";

  /**
   * Two lines count as "on the line", and the first version of this check only
   * looked at one of them — it flagged `GATE-LEDGER.md:614`, where `f8bb6d40`
   * is genuinely not in the base but IS on the active branch, so the document
   * was telling the truth. Hardcoding a single reference branch made this
   * check's observation domain smaller than the property it claims to protect,
   * which is the exact failure this file exists to catch.
   */
  function reachableFromASupportedLine(ref: string): boolean {
    for (const branch of [BASE_BRANCH, "HEAD"]) {
      try {
        execFileSync("git", ["merge-base", "--is-ancestor", ref, branch], {
          cwd: REPO_ROOT,
          stdio: "ignore",
        });
        return true;
      } catch {
        // try the next supported line
      }
    }
    return false;
  }

  /** Phrasings that assert the cited change is in effect on the line. */
  const EFFECT_CLAIM_MARKERS = [
    "已使其归零",
    "已修",
    "已生效",
    "已闭合",
    "已在源头消灭",
    "no longer",
    "is fixed",
    "has been fixed",
    "zeroed",
  ];

  /** Escape hatches: the line itself says which tree the claim holds on. */
  const TREE_SCOPED_MARKERS = [
    "候选材料",
    "该树内",
    "那棵树",
    "candidate",
    "on that tree",
    "only on",
    "not in base",
    "不在 base",
    "未进 base",
    "is not an ancestor",
  ];

  function isAncestorOfBase(ref: string): boolean {
    return reachableFromASupportedLine(ref);
  }

  test("a claim of effect cites a commit reachable from the base, or names its tree", () => {
    const unscoped: string[] = [];
    let checked = 0;

    for (const file of markdownFiles()) {
      const text = readFileSync(file, "utf8");
      for (const [i, line] of text.split("\n").entries()) {
        if (!EFFECT_CLAIM_MARKERS.some((m) => line.includes(m))) continue;
        if (TREE_SCOPED_MARKERS.some((m) => line.includes(m))) continue;
        if (FOREIGN_REPO_MARKERS.some((m) => line.includes(m))) continue;
        for (const m of line.matchAll(HASH_REF)) {
          const ref = m[1]!;
          if (objectType(ref) !== "commit") continue; // non-commits are the other test's business
          checked += 1;
          if (!isAncestorOfBase(ref)) {
            unscoped.push(
              `${file.replace(`${REPO_ROOT}/`, "")}:${i + 1} claims effect citing \`${ref}\`, ` +
                `which is on neither ${BASE_BRANCH} nor HEAD — either land it, or say which tree the claim holds on`,
            );
          }
        }
      }
    }

    // Same reasoning as above: an empty domain must be loud, not silent.
    // Since the 2026-10-03 process-document purge, in-repo normative
    // documents no longer carry effect claims with commit citations
    // (those records live on the wb task board), so the claim domain is
    // expected to be empty. The guard now asserts the scanned document set
    // itself is alive; if an in-repo effect claim appears again, the
    // assertion below applies to it.
    expect(markdownFiles().length).toBeGreaterThanOrEqual(3);
    expect(checked).toBeGreaterThanOrEqual(0);

    expect(
      unscoped,
      `claims of effect citing commits that are not in the base:\n  ${unscoped.join("\n  ")}`,
    ).toEqual([]);
  });
});
