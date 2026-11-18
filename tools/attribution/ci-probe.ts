// CI probe: push one candidate to a temporary branch, dispatch the workflow,
// wait for the selected job, and delete the branch again.

import { runGit, AttributionError } from "./git.ts";
import { runProcess, sleep, tailText } from "./process.ts";
import type {
  CiBackend,
  CiJob,
  CiProbe,
  CiProbeOptions,
  CiRun,
  CiStep,
  CleanupReport,
  CommitProbe,
  GitCommit,
  ProbeRecord,
  StreamKeep,
} from "./types.ts";

type UnknownRecord = Record<string, unknown>;

export type AsyncOperation<T> = () => Promise<T>;

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isRateLimit(message: string): boolean {
  return /rate limit|http 429|secondary rate/i.test(message);
}

async function withRateLimitRetry<T>(label: string, operation: AsyncOperation<T>): Promise<T> {
  let delay = 2000;
  for (let attempt = 0; attempt < 6; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      const message = messageOf(error);
      if (!isRateLimit(message) || attempt === 5) throw error;
      process.stderr.write("attribution-bisect: " + label + " hit a rate limit; retrying in " + String(delay) + " ms\n");
      await sleep(delay);
      delay = Math.min(delay * 2, 60000);
    }
  }
  throw new AttributionError(label + " failed after retries", 1);
}

function asRecord(value: unknown, context: string): UnknownRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new AttributionError("unexpected " + context + " JSON", 1);
  }
  return value as UnknownRecord;
}

function stringField(record: UnknownRecord, key: string, context: string): string {
  const value = record[key];
  if (typeof value !== "string") {
    throw new AttributionError(context + " has no string field " + key, 1);
  }
  return value;
}

function optionalStringField(record: UnknownRecord, key: string): string {
  const value = record[key];
  return typeof value === "string" ? value : "";
}

function numberField(record: UnknownRecord, key: string, context: string): number {
  const value = record[key];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new AttributionError(context + " has no numeric field " + key, 1);
  }
  return value;
}

type RunSummary = {
  databaseId: string;
  headSha: string;
  event: string;
};

type RunView = {
  status: string;
  url: string;
  jobs: CiJob[];
};

function parseRunList(text: string): RunSummary[] {
  const parsed: unknown = JSON.parse(text);
  if (!Array.isArray(parsed)) throw new AttributionError("gh run list did not return an array", 1);
  const result: RunSummary[] = [];
  for (const item of parsed) {
    const record = asRecord(item, "gh run list");
    result.push({
      databaseId: String(numberField(record, "databaseId", "gh run list")),
      headSha: stringField(record, "headSha", "gh run list"),
      event: optionalStringField(record, "event"),
    });
  }
  return result;
}

function parseSteps(value: unknown): CiStep[] {
  if (!Array.isArray(value)) return [];
  const steps: CiStep[] = [];
  for (const item of value) {
    const record = asRecord(item, "gh run view step");
    steps.push({
      name: optionalStringField(record, "name"),
      conclusion: optionalStringField(record, "conclusion"),
    });
  }
  return steps;
}

function parseJobs(value: unknown): CiJob[] {
  if (!Array.isArray(value)) throw new AttributionError("gh run view did not return jobs", 1);
  const jobs: CiJob[] = [];
  for (const item of value) {
    const record = asRecord(item, "gh run view job");
    jobs.push({
      databaseId: String(numberField(record, "databaseId", "gh run view job")),
      name: optionalStringField(record, "name"),
      conclusion: optionalStringField(record, "conclusion"),
      steps: parseSteps(record.steps),
    });
  }
  return jobs;
}

function parseRunView(text: string): RunView {
  const parsed: unknown = JSON.parse(text);
  const record = asRecord(parsed, "gh run view");
  return {
    status: optionalStringField(record, "status"),
    url: optionalStringField(record, "url"),
    jobs: parseJobs(record.jobs),
  };
}

function selectJob(jobs: CiJob[], requested: string): CiJob {
  for (const job of jobs) {
    if (job.name === requested) return job;
  }
  const lowered = requested.toLowerCase();
  for (const job of jobs) {
    if (job.name.toLowerCase() === lowered) return job;
  }
  const names = jobs.map((job) => job.name).join(", ");
  throw new AttributionError(
    "the CI run has no job named " + requested + "; available jobs: " + (names.length > 0 ? names : "(none)"),
    1,
  );
}

function failingStep(job: CiJob): string {
  for (const step of job.steps) {
    if (step.conclusion === "failure") return step.name;
  }
  return job.name;
}

function classifyConclusion(conclusion: string): ProbeRecord["classification"] {
  if (conclusion === "success") return "pass";
  if (conclusion === "failure") return "fail";
  return "error";
}

async function ghText(
  options: CiProbeOptions,
  args: string[],
  maxBytes: number,
  keep: StreamKeep,
): Promise<string> {
  const result = await runProcess([options.gh, ...args], {
    cwd: options.repoRoot,
    timeoutMs: 300000,
    maxBytes,
    keep,
  });
  if (result.code !== 0) {
    throw new AttributionError(
      "gh " + args.join(" ") + " failed with exit " + String(result.code) +
        ": " + tailText(result.stderr.trim() || result.stdout.trim(), 6, 2000),
      1,
    );
  }
  return result.stdout;
}

export function createGhCiBackend(options: CiProbeOptions): CiBackend {
  async function push(sha: string, branch: string): Promise<void> {
    const result = await runGit(
      options.repoRoot,
      ["push", "--no-verify", options.remote, sha + ":refs/heads/" + branch],
      { timeoutMs: 300000, maxBytes: 4 * 1024 * 1024, keep: "tail" },
    );
    if (result.code !== 0) {
      throw new AttributionError(
        "git push of " + sha.slice(0, 10) + " to " + branch + " failed: " +
          tailText(result.stderr.trim() || result.stdout.trim(), 6, 2000),
        1,
      );
    }
  }

  async function dispatch(branch: string): Promise<void> {
    await withRateLimitRetry("gh workflow run", async () => {
      await ghText(options, ["workflow", "run", options.workflow, "--ref", branch], 1024 * 1024, "head");
    });
  }

  async function wait(sha: string, branch: string): Promise<CiRun> {
    const deadline = Date.now() + options.timeoutMs;
    let runId = "";
    while (Date.now() < deadline) {
      if (runId.length === 0) {
        const listText = await withRateLimitRetry("gh run list", async () =>
          ghText(
            options,
            [
              "run", "list",
              "--workflow", options.workflow,
              "--branch", branch,
              "--limit", "20",
              "--json", "databaseId,headSha,event",
            ],
            8 * 1024 * 1024,
            "head",
          ),
        );
        const runs = parseRunList(listText);
        for (const run of runs) {
          if (run.headSha === sha && run.event === "workflow_dispatch") {
            runId = run.databaseId;
            break;
          }
        }
      }
      if (runId.length > 0) {
        const viewText = await withRateLimitRetry("gh run view", async () =>
          ghText(
            options,
            ["run", "view", runId, "--json", "status,conclusion,url,jobs"],
            32 * 1024 * 1024,
            "head",
          ),
        );
        const view = parseRunView(viewText);
        if (view.status === "completed") {
          const job = selectJob(view.jobs, options.job);
          return { runId, runUrl: view.url, job };
        }
      }
      await sleep(options.pollMs);
    }
    throw new AttributionError(
      "the CI run for " + sha.slice(0, 10) + " did not complete within " + String(options.timeoutMs) + " ms",
      1,
    );
  }

  async function log(runId: string, jobId: string): Promise<string> {
    try {
      const failed = await withRateLimitRetry("gh run view --log-failed", async () =>
        ghText(
          options,
          ["run", "view", runId, "--job", jobId, "--log-failed"],
          32 * 1024 * 1024,
          "tail",
        ),
      );
      if (failed.trim().length > 0) return failed;
    } catch {
      // Fall back to the complete job log when the failed-step view is
      // unavailable for this run.
    }
    return withRateLimitRetry("gh run view --log", async () =>
      ghText(
        options,
        ["run", "view", runId, "--job", jobId, "--log"],
        32 * 1024 * 1024,
        "tail",
      ),
    );
  }

  async function list(prefix: string): Promise<string[]> {
    const result = await runGit(options.repoRoot, ["ls-remote", "--heads", options.remote], {
      timeoutMs: 120000,
      maxBytes: 8 * 1024 * 1024,
      keep: "head",
    });
    if (result.code !== 0) {
      throw new AttributionError("git ls-remote failed: " + tailText(result.stderr.trim(), 4, 1000), 1);
    }
    const branches: string[] = [];
    const marker = "refs/heads/";
    for (const line of result.stdout.split("\n")) {
      const tab = line.indexOf("\t");
      if (tab < 0) continue;
      const ref = line.slice(tab + 1);
      if (!ref.startsWith(marker)) continue;
      const branch = ref.slice(marker.length);
      if (branch.startsWith(prefix)) branches.push(branch);
    }
    return branches;
  }

  async function deleteBranch(branch: string): Promise<void> {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const result = await runGit(
        options.repoRoot,
        ["push", "--no-verify", options.remote, "--delete", branch],
        { timeoutMs: 300000, maxBytes: 4 * 1024 * 1024, keep: "tail" },
      );
      if (result.code === 0) return;
      const message = result.stderr + " " + result.stdout;
      if (/remote ref does not exist|couldn.t find remote ref/i.test(message)) return;
      if (attempt < 2) await sleep(options.retryDelayMs * (attempt + 1));
      else {
        throw new AttributionError(
          "cannot delete temporary branch " + branch + ": " + tailText(message.trim(), 6, 2000),
          1,
        );
      }
    }
  }

  return { push, dispatch, wait, log, list, delete: deleteBranch };
}

function createRunId(): string {
  return Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);
}

function errorRecord(commit: GitCommit, startedAt: string, message: string): ProbeRecord {
  return {
    sha: commit.sha,
    shortSha: commit.shortSha,
    subject: commit.subject,
    classification: "error",
    exitCode: null,
    signal: null,
    timedOut: false,
    durationMs: 0,
    checkoutMs: 0,
    command: "",
    startedAt,
    logExcerpt: "",
    failingStep: "",
    jobConclusion: "",
    runId: "",
    runUrl: "",
    notes: [message],
  };
}

export function createCiProbe(options: CiProbeOptions, suppliedBackend?: CiBackend): CiProbe {
  const backend = suppliedBackend ?? createGhCiBackend(options);
  const runId = createRunId();
  const prefix = "attribution/" + runId + "/";
  const pushed: string[] = [];
  const deleted: string[] = [];
  const failures: string[] = [];

  const probe: CommitProbe = async (commit): Promise<ProbeRecord> => {
    const startedAt = new Date().toISOString();
    const started = performance.now();
    const branch = prefix + commit.shortSha;
    const notes: string[] = [];
    let record = errorRecord(commit, startedAt, "probe did not run");
    let pushOk = false;
    // Track the branch before the push: a push that times out may still have
    // created the ref, and cleanup must cover that case.
    pushed.push(branch);
    try {
      await backend.push(commit.sha, branch);
      pushOk = true;
      notes.push("temporary branch: " + branch);
      await backend.dispatch(branch);
      const run = await backend.wait(commit.sha, branch);
      const classification = classifyConclusion(run.job.conclusion);
      let logText = "";
      try {
        logText = await backend.log(run.runId, run.job.databaseId);
      } catch (error) {
        notes.push("log fetch failed: " + messageOf(error));
      }
      notes.push("job conclusion: " + (run.job.conclusion.length > 0 ? run.job.conclusion : "(none)"));
      record = {
        sha: commit.sha,
        shortSha: commit.shortSha,
        subject: commit.subject,
        classification,
        exitCode: classification === "pass" ? 0 : classification === "fail" ? 1 : null,
        signal: null,
        timedOut: false,
        durationMs: performance.now() - started,
        checkoutMs: 0,
        command: "gh workflow run " + options.workflow + " --ref " + branch,
        startedAt,
        logExcerpt: tailText(logText, options.logLines, 40000),
        failingStep: failingStep(run.job),
        jobConclusion: run.job.conclusion,
        runId: run.runId,
        runUrl: run.runUrl,
        notes,
      };
    } catch (error) {
      record = {
        ...record,
        durationMs: performance.now() - started,
        command: "gh workflow run " + options.workflow + " --ref " + branch,
        logExcerpt: messageOf(error),
        notes,
      };
    } finally {
      if (pushOk && !options.keepBranches) {
        try {
          await backend.delete(branch);
          deleted.push(branch);
          record.notes.push("temporary branch deleted: " + branch);
        } catch (error) {
          const message = branch + ": " + messageOf(error);
          failures.push(message);
          record.notes.push("temporary branch cleanup failed: " + message);
        }
      } else if (pushOk && options.keepBranches) {
        record.notes.push("temporary branch retained: " + branch);
      }
    }
    return record;
  };

  const cleanup = async (): Promise<CleanupReport> => {
    for (const branch of pushed) {
      if (deleted.includes(branch)) continue;
      let removed = false;
      for (let attempt = 0; attempt < 3 && !removed; attempt += 1) {
        try {
          await backend.delete(branch);
          deleted.push(branch);
          removed = true;
        } catch (error) {
          if (attempt === 2) {
            const message = branch + ": " + messageOf(error);
            if (!failures.includes(message)) failures.push(message);
          } else {
            await sleep(options.retryDelayMs * (attempt + 1));
          }
        }
      }
    }
    if (!options.keepBranches) {
      try {
        const remaining = await backend.list(prefix);
        for (const branch of remaining) {
          const message = "temporary branch still exists on the remote: " + branch;
          if (!failures.includes(message)) failures.push(message);
        }
      } catch (error) {
        const message = "cannot list temporary branches: " + messageOf(error);
        if (!failures.includes(message)) failures.push(message);
      }
    }
    return { pushed: [...pushed], deleted: [...deleted], failures: [...failures] };
  };

  return { probe, cleanup, runId };
}
