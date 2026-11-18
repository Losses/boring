// Shared types for the attribution bisect tool.

export type AttributionMode = "local" | "ci";

export type MaterializeMode = "export" | "worktree";

export type ProbeClassification = "pass" | "fail" | "error";

export type StreamKeep = "head" | "tail";

export type GitCommit = {
  sha: string;
  shortSha: string;
  subject: string;
  parents: string[];
};

export type ProbeRecord = {
  sha: string;
  shortSha: string;
  subject: string;
  classification: ProbeClassification;
  exitCode: number | null;
  signal: string | null;
  timedOut: boolean;
  durationMs: number;
  checkoutMs: number;
  command: string;
  startedAt: string;
  logExcerpt: string;
  failingStep: string;
  jobConclusion: string;
  runId: string;
  runUrl: string;
  notes: string[];
};

export type GitRange = {
  repoRoot: string;
  lastGreen: GitCommit;
  red: GitCommit;
  commits: GitCommit[];
  mergeCommits: GitCommit[];
};

export type BisectResult = {
  firstBad: GitCommit;
  lastGood: GitCommit;
  probes: ProbeRecord[];
  steps: number;
};

export type BisectFound = {
  kind: "found";
  result: BisectResult;
};

export type BisectRefused = {
  kind: "refused";
  reason: string;
  exitCode: number;
  probes: ProbeRecord[];
};

export type BisectOutcome = BisectFound | BisectRefused;

export type CommitProbe = (commit: GitCommit, index: number) => Promise<ProbeRecord>;

export type CleanupReport = {
  pushed: string[];
  deleted: string[];
  failures: string[];
};

export type CleanupFn = () => Promise<CleanupReport>;

export type ProcessResult = {
  code: number | null;
  signal: string | null;
  timedOut: boolean;
  durationMs: number;
  stdout: string;
  stderr: string;
  stdoutBytes: Uint8Array | null;
  truncated: boolean;
};

export type RunOptions = {
  cwd?: string;
  env?: Record<string, string>;
  timeoutMs?: number;
  maxBytes?: number;
  keep?: StreamKeep;
  binary?: boolean;
  stdin?: Uint8Array | string;
};

export type GitRunOptions = RunOptions;

export type GitRunner = (repo: string, args: string[], options?: GitRunOptions) => Promise<ProcessResult>;

export type ExportStats = {
  fileCount: number;
  byteCount: number;
  symlinkCount: number;
};

export type CiStep = {
  name: string;
  conclusion: string;
};

export type CiJob = {
  databaseId: string;
  name: string;
  conclusion: string;
  steps: CiStep[];
};

export type CiRun = {
  runId: string;
  runUrl: string;
  job: CiJob;
};

export type CiPushFn = (sha: string, branch: string) => Promise<void>;

export type CiDispatchFn = (branch: string) => Promise<void>;

export type CiWaitFn = (sha: string, branch: string) => Promise<CiRun>;

export type CiLogFn = (runId: string, jobId: string) => Promise<string>;

export type CiListFn = (prefix: string) => Promise<string[]>;

export type CiDeleteFn = (branch: string) => Promise<void>;

export type CiBackend = {
  push: CiPushFn;
  dispatch: CiDispatchFn;
  wait: CiWaitFn;
  log: CiLogFn;
  list: CiListFn;
  delete: CiDeleteFn;
};

export type CiProbeOptions = {
  repoRoot: string;
  workflow: string;
  job: string;
  remote: string;
  gh: string;
  pollMs: number;
  timeoutMs: number;
  retryDelayMs: number;
  logLines: number;
  keepBranches: boolean;
};

export type CiProbe = {
  probe: CommitProbe;
  cleanup: CleanupFn;
  runId: string;
};
