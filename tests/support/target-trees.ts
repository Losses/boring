/**
 * Generated-target-tree availability.
 *
 * The cross-target tests under `tests/ts/**` assert that *every* target emits a
 * ruled shape. Those assertions read the generated trees at
 * `reference/<target>/gen`, which are git-ignored build output. When a target's
 * toolchain is unavailable on the host -- the two Swift trees cannot be
 * generated locally because the nix `swiftc` FHS wrapper needs unprivileged
 * user namespaces, which this host refuses -- the read throws ENOENT and the
 * assertion is counted as a *failure*. "This host lacks a toolchain" then reads
 * exactly like "the emitter is broken": the reader cannot tell the two apart
 * and the pass/fail baseline drifts with the environment.
 *
 * This module makes that difference explicit and keeps it visible. A test is
 * declared inapplicable in one of two ways, both about the same fact (the tree
 * is absent) and neither weakening an expectation:
 *
 *   (a) the whole case is about one target -> register it with
 *       `test.skipIf(targetTreeUnavailable("swift"))(name, fn)`. The runner
 *       itself prints `(skip) <name>` and folds the case into its skip count.
 *
 *   (b) one case spans several targets -> wrap that target's assertion group in
 *       `withTargetTree("swift", site, () => { ... })`. The group runs when the
 *       tree is present; when it is absent the group is declared inapplicable
 *       and reported, while the other targets' groups in the same case still
 *       run.
 *
 * A present tree is never softened: `withTargetTree` runs the body unchanged
 * and a read that still throws ENOENT for a *present* tree is an emitter defect
 * and must fail. Only the verdict for an absent tree changes -- inapplicable,
 * never "passed".
 *
 * Reporting is not optional, because a declaration that produced no output
 * would be a silent drop -- worse than ENOENT, since nothing would be counted.
 * Every inapplicable group prints a line as it is declared, and
 * `installTargetTreeReport` adds a per-file tally (target names and counts)
 * when that file's tests finish. Call it once, before any other export here.
 */
import { afterAll } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

export type TargetId =
  | "ts"
  | "kotlin"
  | "kotlin-f32"
  | "rust"
  | "rust-f32"
  | "dart"
  | "swift"
  | "swift-f32";

interface TargetTreeDecl {
  /** Workspace-relative generated-tree root. */
  readonly root: string;
  /** What has to be installed (and working) to produce this tree. */
  readonly toolchain: string;
}

const TARGET_TREES: Record<TargetId, TargetTreeDecl> = {
  ts: { root: "reference/ts/gen", toolchain: "the reflaxe TS target" },
  kotlin: { root: "reference/kotlin/gen", toolchain: "the reflaxe Kotlin target" },
  "kotlin-f32": { root: "reference/kotlin-f32/gen", toolchain: "the reflaxe Kotlin target (f32)" },
  rust: { root: "reference/rust/gen", toolchain: "the reflaxe Rust target" },
  "rust-f32": { root: "reference/rust-f32/gen", toolchain: "the reflaxe Rust target (f32)" },
  dart: { root: "reference/dart/gen", toolchain: "the reflaxe Dart target" },
  swift: {
    root: "reference/swift/gen",
    toolchain:
      "the reflaxe Swift target and a working swiftc; the nix FHS wrapper needs unprivileged user namespaces",
  },
  "swift-f32": {
    root: "reference/swift-f32/gen",
    toolchain:
      "the reflaxe Swift target (f32) and a working swiftc; the nix FHS wrapper needs unprivileged user namespaces",
  },
};

export const WORKSPACE_ROOT = path.resolve(import.meta.dir, "../..");

const availability = new Map<TargetId, boolean>();

/** Workspace-relative root of the target's generated tree, e.g. `reference/swift/gen`. */
export function targetTreePath(id: TargetId): string {
  return TARGET_TREES[id].root;
}

export function targetTreeDir(id: TargetId): string {
  return path.join(WORKSPACE_ROOT, TARGET_TREES[id].root);
}

/**
 * A tree counts as present when its root exists and holds at least one entry.
 * A stray empty directory is not a generated tree, and treating it as one would
 * turn every assertion over it back into a file-not-found failure.
 */
export function targetTreeAvailable(id: TargetId): boolean {
  const cached = availability.get(id);
  if (cached !== undefined) return cached;
  let present = false;
  try {
    const dir = targetTreeDir(id);
    present = fs.statSync(dir).isDirectory() && fs.readdirSync(dir).length > 0;
  } catch {
    present = false;
  }
  availability.set(id, present);
  return present;
}

/** Why the tree is absent, for a report line. Only meaningful when it is absent. */
export function targetTreeReason(id: TargetId): string {
  const decl = TARGET_TREES[id];
  return `${decl.root} is absent (it is produced by ${decl.toolchain})`;
}

/**
 * `true` when the target's tree is absent, i.e. when a case wholly about this
 * target must be declared inapplicable rather than run. Read this at test
 * *registration* time, so the runner records a skip:
 *
 *   test.skipIf(targetTreeUnavailable("swift"))("Swift emits ...", () => { ... });
 */
export function targetTreeUnavailable(id: TargetId): boolean {
  const missing = !targetTreeAvailable(id);
  const counts = ledger();
  counts.consulted.add(id);
  if (missing) bump(counts.cases, id);
  return missing;
}

/**
 * Run `body` -- one target's assertion group inside a case that spans several
 * targets -- when that target's tree is present; otherwise declare the group
 * inapplicable and report it. `site` names the group so the report is readable
 * without the call site in view.
 */
export function withTargetTree(id: TargetId, site: string, body: () => void): void {
  const counts = ledger();
  counts.consulted.add(id);
  if (targetTreeAvailable(id)) {
    body();
    return;
  }
  bump(counts.groups, id);
  console.log(`[target-tree] inapplicable: target ${id} — ${targetTreeReason(id)} — group: ${site}`);
}

/**
 * The subset of `ids` whose trees are present, for a scan that walks one tree
 * per target (`walk("reference/swift/gen")`, a table of per-target file rows,
 * ...). Each absent target is declared inapplicable and reported, so the rows
 * it removes from the scan are still counted in the output.
 */
export function availableTargets(ids: readonly TargetId[], site: string): TargetId[] {
  const counts = ledger();
  const present: TargetId[] = [];
  for (const id of ids) {
    counts.consulted.add(id);
    if (targetTreeAvailable(id)) present.push(id);
    else {
      bump(counts.groups, id);
      console.log(
        `[target-tree] inapplicable: target ${id} — ${targetTreeReason(id)} — scan: ${site}`,
      );
    }
  }
  return present;
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

/** Per-file tallies. Files run one after another, and the report closes one file
 *  before the next file's `installTargetTreeReport` opens a fresh ledger. */
interface FileLedger {
  readonly label: string;
  readonly consulted: Set<TargetId>;
  readonly groups: Map<TargetId, number>;
  readonly cases: Map<TargetId, number>;
}

function bump(map: Map<TargetId, number>, id: TargetId): void {
  map.set(id, (map.get(id) ?? 0) + 1);
}

let active: FileLedger | null = null;

function ledger(): FileLedger {
  if (active === null) {
    active = {
      label: "(installTargetTreeReport was not called in this file)",
      consulted: new Set<TargetId>(),
      groups: new Map<TargetId, number>(),
      cases: new Map<TargetId, number>(),
    };
  }
  return active;
}

/**
 * Register the per-file report. Call once per affected test file, before any
 * other export here. It prints a tally naming every target this file asked
 * about that is absent, with how many assertion groups and skip cases that
 * made inapplicable.
 */
export function installTargetTreeReport(label: string): void {
  const ledgerForFile: FileLedger = {
    label,
    consulted: new Set<TargetId>(),
    groups: new Map<TargetId, number>(),
    cases: new Map<TargetId, number>(),
  };
  active = ledgerForFile;
  afterAll(() => {
    const absent = [...ledgerForFile.consulted].filter((id) => !targetTreeAvailable(id));
    if (absent.length === 0) return;
    const detail = absent.map((id) =>
      `${id} [${targetTreeReason(id)}; declared inapplicable: ${ledgerForFile.groups.get(id) ?? 0} assertion group(s), ${ledgerForFile.cases.get(id) ?? 0} skipped case(s)]`,
    );
    const groups = absent.reduce((n, id) => n + (ledgerForFile.groups.get(id) ?? 0), 0);
    const cases = absent.reduce((n, id) => n + (ledgerForFile.cases.get(id) ?? 0), 0);
    console.log(
      `[target-tree] ${path.relative(WORKSPACE_ROOT, label)}: ${absent.length} target tree(s) unavailable — ${detail.join("; ")} — total ${groups} assertion group(s) and ${cases} case(s) were NOT run on this host. Inapplicable, not failed, and not coverage.`,
    );
  });
}
