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

const HOOK_NAMES: ReadonlyArray<string> = ["pre-commit", "commit-msg"];

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
