#!/usr/bin/env bun
/**
 * Installs the repository git hooks from tools/git-hooks/ into .git/hooks/.
 * Run once after cloning: bun tools/git-hooks/install.ts
 *
 * An existing hook file with different content moves aside once, to
 * <name>.before-boring, and the repository hook takes its place. Running
 * the installer again is safe and restores the same hooks.
 */

import { chmodSync, renameSync } from "node:fs";
import { resolve } from "node:path";

// pre-merge-commit is the section 3.4 item 1 enforcement point: it runs the
// pre-merge three-check gate before a mainline merge.
//
// pre-push closes the fast-forward hole in that same gate. A fast-forward merge
// creates no merge commit, so pre-merge-commit never fires; by push time the
// candidate is already on the mainline. pre-push refuses that advance and
// directs the operator to --no-ff, which does trigger the gate. It reaches that
// verdict from the reflog's Fast-forward marker and from a cross-branch direct
// push, so a routine --no-ff merge and its push (reflog reads "Merge made by
// the 'ort' strategy") pass through untouched.
//
// An earlier revision of this installer left pre-push out, on the belief that
// any pre-push hook must consult the pre-merge gate about the mainline itself
// and would therefore refuse every ordinary push. That was measured and is
// false: this hook does not query the gate for ordinary pushes. The remaining
// bypasses it does NOT cover are listed in tools/git-hooks/pre-push and in
// audit-reports/d2-ff-bypass-2026-10-01.md.
const HOOK_NAMES: ReadonlyArray<string> = [
  "pre-commit",
  "commit-msg",
  "pre-merge-commit",
  "pre-push",
];

async function main(): Promise<number> {
  const repoRoot = resolve(import.meta.dir, "..", "..");
  const sourceDir = resolve(repoRoot, "tools", "git-hooks");
  const targetDir = resolve(repoRoot, ".git", "hooks");
  for (const name of HOOK_NAMES) {
    const source = resolve(sourceDir, name);
    const target = resolve(targetDir, name);
    const desired = await Bun.file(source).text();
    const targetFile = Bun.file(target);
    if (await targetFile.exists()) {
      const current = await targetFile.text();
      if (current !== desired) {
        const backup = resolve(targetDir, `${name}.before-boring`);
        renameSync(target, backup);
        console.log(`moved existing ${name} to ${name}.before-boring`);
      }
    }
    await Bun.write(target, desired);
    chmodSync(target, 0o755);
    console.log(`installed ${name}`);
  }
  return 0;
}

if (import.meta.main) {
  process.exit(await main());
}
