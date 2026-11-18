#!/usr/bin/env bun
// Command line entry point for the attribution bisect tool.

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseArgs, UsageError, usage } from "./args.ts";
import type { CliOptions } from "./args.ts";
import { runBisect } from "./bisect.ts";
import { createCiProbe } from "./ci-probe.ts";
import { AttributionError, resolveGitRange } from "./git.ts";
import { createLocalProbe } from "./local-probe.ts";
import { buildReport, jsonReport, printSummary } from "./report.ts";
import type { CleanupFn, CleanupReport, CommitProbe } from "./types.ts";

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function reportError(error: unknown): number {
  if (error instanceof UsageError || error instanceof AttributionError) {
    process.stderr.write("attribution-bisect: " + error.message + "\n");
    if (error instanceof UsageError) process.stderr.write(usage() + "\n");
    return error.exitCode;
  }
  process.stderr.write("attribution-bisect: error: " + messageOf(error) + "\n");
  return 1;
}

function emptyCleanup(): Promise<CleanupReport> {
  return Promise.resolve({ pushed: [], deleted: [], failures: [] });
}

function installSignalHandlers(cleanup: CleanupFn): void {
  let stopping = false;
  const stop = (signal: string): void => {
    if (stopping) return;
    stopping = true;
    process.stderr.write("attribution-bisect: " + signal + " received; deleting temporary branches\n");
    void cleanup()
      .then((result) => {
        for (const failure of result.failures) {
          process.stderr.write("attribution-bisect: cleanup failure: " + failure + "\n");
        }
        process.exit(130);
      })
      .catch((error: unknown) => {
        process.stderr.write("attribution-bisect: cleanup error: " + messageOf(error) + "\n");
        process.exit(130);
      });
  };
  process.once("SIGINT", () => {
    stop("SIGINT");
  });
  process.once("SIGTERM", () => {
    stop("SIGTERM");
  });
}

export async function main(argv: string[]): Promise<number> {
  let options: CliOptions;
  try {
    options = parseArgs(argv);
  } catch (error) {
    return reportError(error);
  }
  if (options.help) {
    process.stdout.write(usage() + "\n");
    return 0;
  }
  const entryPath = process.argv[1] ?? "tools/attribution/cli.ts";
  try {
    const range = await resolveGitRange(options.repo, options.lastGreen, options.red);
    let probe: CommitProbe;
    let cleanup: CleanupFn = emptyCleanup;
    if (options.mode === "local") {
      probe = createLocalProbe({
        repoRoot: range.repoRoot,
        command: options.command,
        materialize: options.materialize,
        timeoutMs: options.timeoutMs,
        logLines: options.logLines,
        stepLabel: options.stepLabel,
        keepCheckout: options.keepCheckout,
      });
    } else {
      const ci = createCiProbe({
        repoRoot: range.repoRoot,
        workflow: options.workflow,
        job: options.job,
        remote: options.remote,
        gh: options.gh,
        pollMs: options.pollMs,
        timeoutMs: options.ciTimeoutMs,
        retryDelayMs: 2000,
        logLines: options.logLines,
        keepBranches: options.keepBranches,
      });
      probe = ci.probe;
      cleanup = ci.cleanup;
      installSignalHandlers(ci.cleanup);
    }
    const outcome = await runBisect(range, probe);
    const cleanupReport = await cleanup();
    const exitCode = cleanupReport.failures.length > 0 ? 4 : outcome.kind === "found" ? 0 : outcome.exitCode;
    const report = buildReport({
      options,
      argv,
      entryPath,
      range,
      outcome,
      cleanup: cleanupReport,
      exitCode,
    });
    if (options.jsonPath === "-") {
      process.stdout.write(jsonReport(report));
    } else {
      printSummary(report);
      if (options.jsonPath.length > 0) {
        const target = resolve(options.jsonPath);
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, jsonReport(report));
        process.stderr.write("attribution-bisect: report written to " + target + "\n");
      }
    }
    if (cleanupReport.failures.length > 0) {
      for (const failure of cleanupReport.failures) {
        process.stderr.write("attribution-bisect: cleanup failure: " + failure + "\n");
      }
    }
    return exitCode;
  } catch (error) {
    return reportError(error);
  }
}

if (import.meta.main) {
  const exitCode = await main(process.argv.slice(2));
  process.exitCode = exitCode;
}
