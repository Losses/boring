// Human and JSON reports for one attribution run.

import type { CliOptions } from "./args.ts";
import type {
  BisectOutcome,
  CleanupReport,
  GitCommit,
  GitRange,
  ProbeRecord,
} from "./types.ts";

export type CommitSummary = {
  sha: string;
  shortSha: string;
  subject: string;
  parents: string[];
};

export type RangeSummary = {
  lastGreen: string;
  red: string;
  commitCount: number;
  commitsAfterLastGreen: number;
  mergeCommitCount: number;
  firstParent: boolean;
};

export type Reproduce = {
  toolCommand: string;
  checkout: string;
  command: string;
  shell: string;
};

export type AttributionReport = {
  tool: string;
  version: number;
  mode: string;
  materialize: string;
  repo: string;
  workflow: string;
  job: string;
  range: RangeSummary;
  outcome: string;
  reason: string;
  exitCode: number;
  firstBadCommit: CommitSummary | null;
  lastGoodCommit: CommitSummary | null;
  failingStep: string;
  firstBadExitCode: number | null;
  logExcerpt: string;
  steps: number;
  probes: ProbeRecord[];
  reproduce: Reproduce;
  cleanup: CleanupReport;
  notes: string[];
};

export type ReportInput = {
  options: CliOptions;
  argv: string[];
  entryPath: string;
  range: GitRange;
  outcome: BisectOutcome;
  cleanup: CleanupReport;
  exitCode: number;
};

function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(value)) return value;
  return "'" + value.replace(/'/g, "'\\''") + "'";
}

function summarize(commit: GitCommit): CommitSummary {
  return {
    sha: commit.sha,
    shortSha: commit.shortSha,
    subject: commit.subject,
    parents: commit.parents,
  };
}

function findProbe(probes: ProbeRecord[], sha: string): ProbeRecord | undefined {
  for (const probe of probes) {
    if (probe.sha === sha) return probe;
  }
  return undefined;
}

function formatDuration(ms: number): string {
  if (ms >= 1000) return (ms / 1000).toFixed(1) + "s";
  return Math.round(ms) + "ms";
}

function buildReproduce(input: ReportInput, firstBad: GitCommit): Reproduce {
  const options = input.options;
  const sha = firstBad.sha;
  const repo = shellQuote(options.repo);
  const command = options.mode === "local" ? options.command : "gh workflow run " + options.workflow + " --ref <temp-branch>";
  const tempBranch = "attribution/<run-id>/" + firstBad.shortSha;
  let checkout: string;
  let shell: string;
  if (options.mode === "local" && options.materialize === "worktree") {
    checkout = "git -C " + repo + " worktree add --detach <checkout-dir> " + sha;
    shell = checkout + " && (cd <checkout-dir> && " + command + ")";
  } else if (options.mode === "local") {
    checkout = "mkdir -p <checkout-dir> && git -C " + repo + " archive " + sha + " | tar -x -C <checkout-dir>";
    shell = checkout + " && (cd <checkout-dir> && " + command + ")";
  } else {
    checkout = "git -C " + repo + " push " + shellQuote(options.remote) + " " + sha + ":refs/heads/" + tempBranch;
    shell = checkout + " && gh workflow run " + options.workflow + " --ref " + tempBranch;
  }
  return {
    toolCommand: ["bun", input.entryPath, ...input.argv].map(shellQuote).join(" "),
    checkout,
    command,
    shell,
  };
}

export function buildReport(input: ReportInput): AttributionReport {
  const outcome = input.outcome;
  const found = outcome.kind === "found";
  const firstBad = found ? outcome.result.firstBad : null;
  const lastGood = found ? outcome.result.lastGood : null;
  const probes = found ? outcome.result.probes : outcome.probes;
  const firstBadProbe = firstBad === null ? undefined : findProbe(probes, firstBad.sha);
  const notes: string[] = [];
  if (input.range.mergeCommits.length > 0) {
    notes.push(
      "the first-parent chain contains " + String(input.range.mergeCommits.length) +
        " merge commits; the report identifies the first failing mainline commit",
    );
  }
  if (input.options.mode === "local") {
    notes.push(input.options.keepCheckout
      ? "each candidate is checked out under a temporary directory; the checkouts are retained"
      : "each candidate was checked out under a temporary directory and removed after the probe");
  }
  if (input.options.mode === "local" && input.options.materialize === "export") {
    notes.push("export materialization reads the commit through git ls-tree and git cat-file");
  }
  if (input.options.mode === "ci") {
    notes.push("CI probes run one at a time; every temporary branch is deleted after its probe");
  }
  for (const failure of input.cleanup.failures) {
    notes.push("cleanup failure: " + failure);
  }
  const reproduce = firstBad === null
    ? {
      toolCommand: ["bun", input.entryPath, ...input.argv].map(shellQuote).join(" "),
      checkout: "(no failing commit)",
      command: input.options.command,
      shell: "(no failing commit)",
    }
    : buildReproduce(input, firstBad);
  return {
    tool: "attribution-bisect",
    version: 1,
    mode: input.options.mode,
    materialize: input.options.materialize,
    repo: input.range.repoRoot,
    workflow: input.options.workflow,
    job: input.options.job,
    range: {
      lastGreen: input.range.lastGreen.sha,
      red: input.range.red.sha,
      commitCount: input.range.commits.length,
      commitsAfterLastGreen: input.range.commits.length - 1,
      mergeCommitCount: input.range.mergeCommits.length,
      firstParent: true,
    },
    outcome: found ? "found" : "refused",
    reason: found ? "" : outcome.reason,
    exitCode: input.exitCode,
    firstBadCommit: firstBad === null ? null : summarize(firstBad),
    lastGoodCommit: lastGood === null ? null : summarize(lastGood),
    failingStep: firstBadProbe === undefined ? "" : firstBadProbe.failingStep,
    firstBadExitCode: firstBadProbe === undefined ? null : firstBadProbe.exitCode,
    logExcerpt: firstBadProbe === undefined ? "" : firstBadProbe.logExcerpt,
    steps: found ? outcome.result.steps : 0,
    probes,
    reproduce,
    cleanup: input.cleanup,
    notes,
  };
}

export function printSummary(report: AttributionReport): void {
  const lines: string[] = [];
  const found = report.outcome === "found";
  lines.push("attribution-bisect: " + (found ? "first bad commit" : "refused"));
  lines.push(
    "  range: " + report.range.lastGreen.slice(0, 10) + ".." + report.range.red.slice(0, 10) +
      " (" + String(report.range.commitCount) + " commits in chain, " +
      String(report.range.commitsAfterLastGreen) + " after last-green, first-parent" +
      (report.range.mergeCommitCount > 0 ? ", " + String(report.range.mergeCommitCount) + " merges" : "") + ")",
  );
  if (found && report.firstBadCommit !== null) {
    lines.push("  first bad: " + report.firstBadCommit.sha + " " + report.firstBadCommit.subject);
    lines.push("  failing step: " + (report.failingStep.length > 0 ? report.failingStep : "(not recorded)"));
    lines.push("  probe exit: " + String(report.firstBadExitCode));
    lines.push("  bisect steps: " + String(report.steps) + " (" + String(report.probes.length) + " probes)");
  } else {
    lines.push("  reason: " + report.reason);
    lines.push("  probes: " + String(report.probes.length));
  }
  if (report.probes.length > 0) {
    lines.push("  probe trace:");
    for (const probe of report.probes) {
      const exit = probe.exitCode === null ? "n/a" : String(probe.exitCode);
      lines.push(
        "    " + probe.classification + " " + probe.shortSha + " exit " + exit +
          " " + formatDuration(probe.durationMs) +
          (probe.jobConclusion.length > 0 ? " job " + probe.jobConclusion : ""),
      );
    }
  }
  if (report.logExcerpt.length > 0) {
    lines.push("  log excerpt:");
    for (const line of report.logExcerpt.split("\n")) lines.push("    " + line);
  }
  lines.push("  reproduce:");
  lines.push("    " + report.reproduce.toolCommand);
  lines.push("  checkout:");
  lines.push("    " + report.reproduce.checkout);
  lines.push("  command:");
  lines.push("    " + report.reproduce.command);
  if (report.cleanup.pushed.length > 0 || report.cleanup.failures.length > 0) {
    lines.push(
      "  cleanup: deleted " + String(report.cleanup.deleted.length) + " of " +
        String(report.cleanup.pushed.length) + " temporary branches",
    );
    for (const failure of report.cleanup.failures) lines.push("    failure: " + failure);
  }
  process.stdout.write(lines.join("\n") + "\n");
}

export function jsonReport(report: AttributionReport): string {
  return JSON.stringify(report, null, 2) + "\n";
}
