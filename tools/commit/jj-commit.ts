#!/usr/bin/env bun
/**
 * Commit helper for a jj workspace.
 *
 * jj runs no git hooks (its Git compatibility table records "Hooks: No."), and
 * an alias cannot replace a built-in command, so a jj workspace never runs
 * tools/git-hooks/pre-commit. A plain `jj commit` therefore carried six
 * documentation-style candidates onto master while the git hook stayed
 * silent. This tool puts the zero-tolerance documentation style check in
 * front of that commit and validates the message with the same rules as
 * tools/commit/commit.ts:
 *
 *     bun tools/commit/jj-commit.ts "<full commit message>"
 *
 * The check is the one the git hook runs: a numeric hit count is required, and
 * the commit is refused unless the count is zero with exit status 0. A check
 * that could not be measured is a failure. The jj binary comes from JJ_BIN
 * when it is set, and from PATH otherwise.
 */

import { $ } from "bun";
import { resolve } from "node:path";
import { usageText, validateCommitMessage } from "./message.ts";
import type { CommitIssue } from "./message.ts";

const REPO_ROOT = resolve(import.meta.dir, "..", "..");
const DOC_STYLE_CHECK = resolve(REPO_ROOT, "tools", "doc-style", "check.ts");
const HIT_COUNT = /^hits: ([0-9]+)\.$/;

function reportIssues(issues: ReadonlyArray<CommitIssue>): void {
  for (const issue of issues) {
    console.error(`commit message line ${issue.line}: [${issue.rule}] ${issue.problem}`);
  }
  console.error();
  console.error(usageText());
}

// The git hook reads the last "hits: N." line and treats a missing count as a
// failure; this reads the same line from the same checker.
function reportedHits(stdout: string): number | undefined {
  let hits: number | undefined;
  for (const rawLine of stdout.split("\n")) {
    const match = HIT_COUNT.exec(rawLine.trim());
    if (match !== null && match[1] !== undefined) hits = Number(match[1]);
  }
  return hits;
}

async function checkDocumentationStyle(): Promise<number> {
  const result = await $`bun ${DOC_STYLE_CHECK}`.cwd(REPO_ROOT).nothrow().quiet();
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  if (stdout.length > 0) process.stdout.write(stdout);
  if (stderr.length > 0) process.stderr.write(stderr);
  const hits = reportedHits(stdout);
  if (hits === undefined) {
    console.error("jj-commit: check.ts did not report a numeric hit count; refusing");
    return 1;
  }
  if (hits !== 0 || result.exitCode !== 0) {
    console.error(`jj-commit: documentation style is not clean: ${hits} hits (rc=${result.exitCode}); fix them before committing`);
    return 1;
  }
  return 0;
}

async function main(args: ReadonlyArray<string>): Promise<number> {
  if (args.length === 0) {
    console.error("usage: bun tools/commit/jj-commit.ts \"<full commit message>\"");
    console.error();
    console.error(usageText());
    return 2;
  }
  const message = args.join(" ");
  const issues = validateCommitMessage(message);
  if (issues.length > 0) {
    reportIssues(issues);
    return 1;
  }
  if ((await checkDocumentationStyle()) !== 0) return 1;
  const jjBinary = process.env.JJ_BIN ?? "jj";
  const result = await $`${jjBinary} commit -m ${message}`.nothrow();
  const stdout = result.stdout.toString();
  const stderr = result.stderr.toString();
  if (stdout.length > 0) process.stdout.write(stdout);
  if (stderr.length > 0) process.stderr.write(stderr);
  if (result.exitCode !== 0) {
    console.error(`jj-commit: jj commit failed with exit code ${result.exitCode}`);
    return result.exitCode ?? 1;
  }
  return 0;
}

if (import.meta.main) {
  process.exit(await main(process.argv.slice(2)));
}
