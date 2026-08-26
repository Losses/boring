#!/usr/bin/env bun
/**
 * Conventional commit helper for the boring repository.
 *
 * Usage:
 *     bun tools/commit/commit.ts "<full commit message>"   validate and commit
 *     bun tools/commit/commit.ts --check FILE              validate a message file
 *
 * The tool commits what is staged; it never stages or adds files. It rejects
 * messages that violate Conventional Commits v1.0.0 and messages that carry
 * a Co-Authored-By trailer. On every rejection it prints the rule and the
 * correct format. AGENT.md names this tool as the only permitted commit
 * entry point.
 */

import { $ } from "bun";
import { usageText, validateCommitMessage } from "./message.ts";
import type { CommitIssue } from "./message.ts";

function reportIssues(issues: ReadonlyArray<CommitIssue>): void {
  for (const issue of issues) {
    console.error(`commit message line ${issue.line}: [${issue.rule}] ${issue.problem}`);
  }
  console.error();
  console.error(usageText());
}

async function runCheck(path: string): Promise<number> {
  const message = await Bun.file(path).text();
  const issues = validateCommitMessage(message);
  if (issues.length > 0) {
    reportIssues(issues);
    return 1;
  }
  console.log("commit message ok");
  return 0;
}

async function runCommit(message: string): Promise<number> {
  const issues = validateCommitMessage(message);
  if (issues.length > 0) {
    reportIssues(issues);
    return 1;
  }
  const staged = await $`git diff --cached --quiet`.nothrow().quiet();
  if (staged.exitCode === 0) {
    console.error("nothing is staged; stage files with git add before committing");
    return 1;
  }
  const result = await $`git commit -m ${message}`.nothrow();
  if (result.exitCode !== 0) {
    console.error(`git commit failed with exit code ${result.exitCode}`);
    return result.exitCode;
  }
  return 0;
}

async function main(args: ReadonlyArray<string>): Promise<number> {
  if (args.length === 0) {
    console.error(usageText());
    return 2;
  }
  if (args[0] === "--check") {
    const path = args[1];
    if (path === undefined) {
      console.error("--check needs a message file path");
      return 2;
    }
    return runCheck(path);
  }
  return runCommit(args.join(" "));
}

if (import.meta.main) {
  process.exit(await main(process.argv.slice(2)));
}
