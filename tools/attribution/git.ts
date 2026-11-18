// Git range resolution, commit export, and temporary worktree management.

import { chmodSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, normalize, resolve, sep } from "node:path";
import { runProcess, tailText } from "./process.ts";
import type {
  ExportStats,
  GitCommit,
  GitRange,
  GitRunOptions,
  GitRunner,
  ProcessResult,
} from "./types.ts";

export class AttributionError extends Error {
  readonly exitCode: number;

  constructor(message: string, exitCode: number) {
    super(message);
    this.name = "AttributionError";
    this.exitCode = exitCode;
  }
}

export class AttributionRangeError extends AttributionError {
  constructor(message: string) {
    super(message, 2);
    this.name = "AttributionRangeError";
  }
}

export async function runGit(
  repo: string,
  args: string[],
  options: GitRunOptions = {},
): Promise<ProcessResult> {
  return runProcess(["git", "-C", repo, ...args], options);
}

export async function gitOrThrow(
  repo: string,
  args: string[],
  options: GitRunOptions = {},
): Promise<ProcessResult> {
  const result = await runGit(repo, args, options);
  if (result.code !== 0) {
    const detail = tailText(result.stderr.trim() || result.stdout.trim(), 6, 2000);
    throw new AttributionError(
      "git " + args.join(" ") + " failed with exit " + String(result.code) + (detail.length > 0 ? ": " + detail : ""),
      1,
    );
  }
  return result;
}

function shortSha(sha: string): string {
  return sha.slice(0, 10);
}

async function resolveCommit(repo: string, revision: string, runner: GitRunner): Promise<string> {
  const result = await runner(repo, ["rev-parse", "--verify", "--quiet", revision + "^{commit}"], {
    maxBytes: 64 * 1024,
  });
  const sha = result.stdout.trim();
  if (result.code !== 0 || sha.length === 0) {
    throw new AttributionRangeError("cannot resolve " + revision + " to a commit in " + repo);
  }
  return sha;
}

async function isAncestor(repo: string, ancestor: string, descendant: string, runner: GitRunner): Promise<boolean> {
  const result = await runner(repo, ["merge-base", "--is-ancestor", ancestor, descendant], {
    maxBytes: 64 * 1024,
  });
  if (result.code === 0) return true;
  if (result.code === 1) return false;
  throw new AttributionError(
    "git merge-base --is-ancestor failed: " + tailText(result.stderr.trim(), 4, 1000),
    1,
  );
}

function parseCommitSubject(record: string): GitCommit {
  const parts = record.split("\u001f");
  const sha = parts[0] ?? "";
  const parentText = parts[1] ?? "";
  const subject = parts.slice(2).join("\u001f");
  if (sha.length === 0) throw new AttributionError("git log returned an empty commit id", 1);
  const parents = parentText.length > 0 ? parentText.split(" ").filter((parent) => parent.length > 0) : [];
  return { sha, shortSha: shortSha(sha), subject, parents };
}

async function readCommitHeader(repo: string, sha: string, runner: GitRunner): Promise<GitCommit> {
  const result = await runner(repo, ["show", "-s", "--format=%H%x1f%P%x1f%s", sha], {
    maxBytes: 64 * 1024,
  });
  if (result.code !== 0) {
    throw new AttributionError("cannot read commit " + sha + ": " + tailText(result.stderr.trim(), 4, 1000), 1);
  }
  return parseCommitSubject(result.stdout.trim());
}

async function isOnFirstParentChain(
  repo: string,
  ancestor: string,
  descendant: string,
  runner: GitRunner,
): Promise<boolean> {
  // The bisect walks the first-parent chain. A last-green commit that is only
  // reachable through a merged branch would make the chain skip mainline
  // commits, so it is rejected before any probe runs.
  const result = await runner(repo, ["log", "--first-parent", "--format=%H", descendant], {
    maxBytes: 32 * 1024 * 1024,
  });
  if (result.code !== 0) {
    throw new AttributionError("cannot read the first-parent chain: " + tailText(result.stderr.trim(), 4, 1000), 1);
  }
  for (const line of result.stdout.split("\n")) {
    if (line.trim() === ancestor) return true;
  }
  return false;
}

export async function resolveGitRange(
  repoArgument: string,
  lastGreenArgument: string,
  redArgument: string,
  runner: GitRunner = runGit,
): Promise<GitRange> {
  const rootResult = await runner(repoArgument, ["rev-parse", "--show-toplevel"], {
    maxBytes: 64 * 1024,
  });
  const repoRoot = rootResult.stdout.trim();
  if (rootResult.code !== 0 || repoRoot.length === 0) {
    throw new AttributionRangeError(repoArgument + " is not a git repository");
  }
  const lastGreenSha = await resolveCommit(repoRoot, lastGreenArgument, runner);
  const redSha = await resolveCommit(repoRoot, redArgument, runner);
  if (lastGreenSha === redSha) {
    throw new AttributionRangeError(
      "last-green and red resolve to the same commit " + shortSha(lastGreenSha) + "; the range is empty",
    );
  }
  const forward = await isAncestor(repoRoot, lastGreenSha, redSha, runner);
  const backward = await isAncestor(repoRoot, redSha, lastGreenSha, runner);
  if (!forward) {
    if (backward) {
      throw new AttributionRangeError(
        "last-green " + shortSha(lastGreenSha) + " is a descendant of red " + shortSha(redSha) +
          "; pass the older commit as --last-green and the newer commit as --red",
      );
    }
    throw new AttributionRangeError(
      "last-green " + shortSha(lastGreenSha) + " and red " + shortSha(redSha) +
        " are not on one ancestry chain; refusing to guess",
    );
  }
  const onChain = await isOnFirstParentChain(repoRoot, lastGreenSha, redSha, runner);
  if (!onChain) {
    throw new AttributionRangeError(
      "last-green " + shortSha(lastGreenSha) + " is an ancestor of red " + shortSha(redSha) +
        " but not on red's first-parent chain; pass a mainline commit as --last-green",
    );
  }
  const lastGreen = await readCommitHeader(repoRoot, lastGreenSha, runner);
  const logResult = await gitOrThrow(
    repoRoot,
    ["log", "--first-parent", "--reverse", "-z", "--format=%H%x1f%P%x1f%s", lastGreenSha + ".." + redSha],
    { maxBytes: 32 * 1024 * 1024 },
  );
  const commits: GitCommit[] = [lastGreen];
  for (const record of logResult.stdout.split("\u0000")) {
    if (record.trim().length === 0) continue;
    commits.push(parseCommitSubject(record));
  }
  const last = commits[commits.length - 1];
  if (last === undefined || last.sha !== redSha) {
    throw new AttributionRangeError(
      "the first-parent chain from " + shortSha(lastGreenSha) + " does not end at red " + shortSha(redSha) +
        "; the range is not a linear mainline interval",
    );
  }
  if (commits.length < 2) {
    throw new AttributionRangeError("the range contains no commit between last-green and red");
  }
  const seen = new Set<string>();
  for (const commit of commits) {
    if (seen.has(commit.sha)) {
      throw new AttributionRangeError("the first-parent chain repeats commit " + shortSha(commit.sha));
    }
    seen.add(commit.sha);
  }
  const mergeCommits = commits.filter((commit) => commit.parents.length > 1);
  return { repoRoot, lastGreen, red: commits[commits.length - 1] as GitCommit, commits, mergeCommits };
}

type TreeEntry = {
  mode: string;
  objectType: string;
  oid: string;
  path: string;
};

function parseTreeEntries(raw: string): TreeEntry[] {
  const entries: TreeEntry[] = [];
  for (const record of raw.split("\u0000")) {
    if (record.length === 0) continue;
    const tab = record.indexOf("\t");
    if (tab < 0) throw new AttributionError("cannot parse git ls-tree output: " + record.slice(0, 160), 1);
    const metadata = record.slice(0, tab).split(" ");
    const path = record.slice(tab + 1);
    const mode = metadata[0] ?? "";
    const objectType = metadata[1] ?? "";
    const oid = metadata[2] ?? "";
    if (mode.length === 0 || objectType.length === 0 || oid.length === 0 || path.length === 0) {
      throw new AttributionError("cannot parse git ls-tree entry: " + record.slice(0, 160), 1);
    }
    entries.push({ mode, objectType, oid, path });
  }
  return entries;
}

function safeDestination(root: string, relativePath: string): string {
  if (isAbsolute(relativePath)) {
    throw new AttributionError("git tree contains an absolute path: " + relativePath, 1);
  }
  const normalized = normalize(relativePath);
  if (normalized === ".." || normalized.startsWith(".." + sep)) {
    throw new AttributionError("git tree path escapes the checkout: " + relativePath, 1);
  }
  const absolute = resolve(root, normalized);
  const base = resolve(root);
  if (absolute !== base && !absolute.startsWith(base + sep)) {
    throw new AttributionError("git tree path escapes the checkout: " + relativePath, 1);
  }
  return absolute;
}

export async function exportCommit(repoRoot: string, sha: string, destination: string): Promise<ExportStats> {
  mkdirSync(destination, { recursive: true });
  const listing = await gitOrThrow(repoRoot, ["ls-tree", "-r", "-z", "--full-tree", sha], {
    maxBytes: 64 * 1024 * 1024,
  });
  const entries = parseTreeEntries(listing.stdout);
  const blobs: TreeEntry[] = [];
  for (const entry of entries) {
    if (entry.objectType === "commit") {
      throw new AttributionError(
        "commit " + sha + " contains the submodule " + entry.path + "; use --materialize worktree",
        1,
      );
    }
    if (entry.objectType !== "blob") {
      throw new AttributionError("unsupported git object type " + entry.objectType + " at " + entry.path, 1);
    }
    blobs.push(entry);
  }
  if (blobs.length === 0) {
    throw new AttributionError("commit " + sha + " has no tracked files", 1);
  }
  const input = blobs.map((entry) => entry.oid).join("\n") + "\n";
  const batch = await runGit(repoRoot, ["cat-file", "--batch"], {
    stdin: input,
    binary: true,
    maxBytes: 512 * 1024 * 1024,
    keep: "head",
    timeoutMs: 300000,
  });
  if (batch.code !== 0) {
    throw new AttributionError(
      "git cat-file --batch failed for " + sha + ": " + tailText(batch.stderr.trim(), 6, 2000),
      1,
    );
  }
  const bytes = batch.stdoutBytes;
  if (bytes === null) throw new AttributionError("git cat-file returned no bytes for " + sha, 1);
  let offset = 0;
  let byteCount = 0;
  let symlinkCount = 0;
  for (const entry of blobs) {
    const newline = bytes.indexOf(10, offset);
    if (newline < 0) {
      throw new AttributionError("truncated git cat-file header for " + entry.path, 1);
    }
    const header = Buffer.from(bytes.subarray(offset, newline)).toString("utf8");
    const fields = header.split(" ");
    const objectType = fields[1] ?? "";
    const size = Number(fields[2] ?? "");
    if (objectType !== "blob" || !Number.isInteger(size) || size < 0) {
      throw new AttributionError("unexpected git cat-file header for " + entry.path + ": " + header, 1);
    }
    const start = newline + 1;
    const end = start + size;
    if (end > bytes.length) {
      throw new AttributionError("truncated git cat-file body for " + entry.path, 1);
    }
    const content = Buffer.from(bytes.subarray(start, end));
    const target = safeDestination(destination, entry.path);
    mkdirSync(dirname(target), { recursive: true });
    if (entry.mode === "120000") {
      symlinkCount += 1;
      if (process.platform === "win32") {
        writeFileSync(target, content);
      } else {
        symlinkSync(content.toString("utf8"), target);
      }
    } else {
      writeFileSync(target, content);
      chmodSync(target, entry.mode === "100755" ? 0o755 : 0o644);
    }
    byteCount += size;
    offset = end + 1;
  }
  return { fileCount: blobs.length, byteCount, symlinkCount };
}

export async function addWorktree(repoRoot: string, sha: string, destination: string): Promise<void> {
  const result = await runGit(repoRoot, ["worktree", "add", "--detach", "--force", destination, sha], {
    timeoutMs: 300000,
    maxBytes: 4 * 1024 * 1024,
    keep: "tail",
  });
  if (result.code !== 0) {
    throw new AttributionError(
      "git worktree add failed for " + shortSha(sha) + ": " + tailText(result.stderr.trim(), 6, 2000),
      1,
    );
  }
}

export async function removeWorktree(repoRoot: string, destination: string): Promise<void> {
  const result = await runGit(repoRoot, ["worktree", "remove", "--force", destination], {
    timeoutMs: 300000,
    maxBytes: 4 * 1024 * 1024,
    keep: "tail",
  });
  if (result.code !== 0) {
    await runGit(repoRoot, ["worktree", "prune"], { timeoutMs: 120000, maxBytes: 1024 * 1024 });
  }
}
