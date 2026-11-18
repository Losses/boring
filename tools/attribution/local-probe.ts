// Local probe: materialize one commit and run the repro command once.

import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { addWorktree, exportCommit, removeWorktree } from "./git.ts";
import { runProcess, tailText } from "./process.ts";
import type { CommitProbe, MaterializeMode, ProbeRecord } from "./types.ts";

export type LocalProbeOptions = {
  repoRoot: string;
  command: string;
  materialize: MaterializeMode;
  timeoutMs: number;
  logLines: number;
  stepLabel: string;
  keepCheckout: boolean;
};

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function combineOutput(stdout: string, stderr: string): string {
  const parts: string[] = [];
  if (stdout.length > 0) parts.push(stdout);
  if (stderr.length > 0) parts.push("--- stderr ---\n" + stderr);
  return parts.join("\n");
}

export function createLocalProbe(options: LocalProbeOptions): CommitProbe {
  return async (commit, index) => {
    const startedAt = new Date().toISOString();
    const started = performance.now();
    const tempRoot = await mkdtemp(join(tmpdir(), "attribution-"));
    const checkout = join(tempRoot, "checkout");
    const notes: string[] = [];
    let checkoutMs = 0;
    let result: Awaited<ReturnType<typeof runProcess>> | null = null;
    let setupError = "";
    try {
      const checkoutStarted = performance.now();
      if (options.materialize === "export") {
        await exportCommit(options.repoRoot, commit.sha, checkout);
        notes.push("materialized from tracked files");
      } else {
        await addWorktree(options.repoRoot, commit.sha, checkout);
        notes.push("materialized as a detached worktree");
      }
      checkoutMs = performance.now() - checkoutStarted;
      result = await runProcess(["bash", "-c", options.command], {
        cwd: checkout,
        env: {
          ATTRIBUTION_REPO: options.repoRoot,
          ATTRIBUTION_SHA: commit.sha,
          ATTRIBUTION_SHORT_SHA: commit.shortSha,
          ATTRIBUTION_PROBE: String(index),
        },
        timeoutMs: options.timeoutMs,
        maxBytes: 8 * 1024 * 1024,
        keep: "tail",
      });
    } catch (error) {
      setupError = messageOf(error);
    }
    const durationMs = performance.now() - started;
    let classification: ProbeRecord["classification"];
    if (setupError.length > 0) {
      classification = "error";
    } else if (result === null) {
      classification = "error";
    } else if (result.timedOut || result.signal !== null) {
      classification = "error";
    } else if (result.code === 0) {
      classification = "pass";
    } else {
      classification = "fail";
    }
    let logExcerpt = "";
    if (setupError.length > 0) {
      logExcerpt = "checkout failed: " + setupError;
      notes.push("checkout failed");
    } else if (result !== null) {
      logExcerpt = tailText(combineOutput(result.stdout, result.stderr), options.logLines, 40000);
      if (result.timedOut) notes.push("probe timed out after " + String(options.timeoutMs) + " ms");
      if (result.signal !== null) notes.push("probe ended on signal " + result.signal);
      if (result.truncated) notes.push("probe output was truncated");
    }
    if (options.keepCheckout) {
      notes.push("checkout retained at " + checkout);
    } else {
      try {
        if (options.materialize === "worktree") {
          await removeWorktree(options.repoRoot, checkout);
        }
        await rm(tempRoot, { recursive: true, force: true });
      } catch (error) {
        notes.push("checkout cleanup failed: " + messageOf(error));
      }
    }
    return {
      sha: commit.sha,
      shortSha: commit.shortSha,
      subject: commit.subject,
      classification,
      exitCode: result === null ? null : result.code,
      signal: result === null ? null : result.signal,
      timedOut: result === null ? false : result.timedOut,
      durationMs,
      checkoutMs,
      command: options.command,
      startedAt,
      logExcerpt,
      failingStep: options.stepLabel,
      jobConclusion: "",
      runId: "",
      runUrl: "",
      notes,
    };
  };
}
