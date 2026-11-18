import { describe, expect, test } from "bun:test";
import { parseArgs, UsageError } from "./args.ts";
import { runBisect } from "./bisect.ts";
import { createCiProbe } from "./ci-probe.ts";
import { AttributionRangeError, resolveGitRange } from "./git.ts";
import type {
  CiBackend,
  CiProbeOptions,
  CiRun,
  CommitProbe,
  GitCommit,
  GitRange,
  GitRunner,
  ProbeClassification,
  ProbeRecord,
  ProcessResult,
} from "./types.ts";

function makeCommit(index: number): GitCommit {
  const suffix = String(index).padStart(4, "0");
  const previous = index === 0 ? null : "commit" + String(index - 1).padStart(4, "0");
  return {
    sha: "commit" + suffix,
    shortSha: "commit" + suffix,
    subject: "commit " + String(index),
    parents: previous === null ? [] : [previous],
  };
}

function makeRange(count: number): GitRange {
  const commits: GitCommit[] = [];
  for (let index = 0; index < count; index += 1) commits.push(makeCommit(index));
  const first = commits[0];
  const last = commits[commits.length - 1];
  if (first === undefined || last === undefined) throw new Error("empty range");
  return { repoRoot: "/repo", lastGreen: first, red: last, commits, mergeCommits: [] };
}

function commitAt(range: GitRange, index: number): GitCommit {
  const commit = range.commits[index];
  if (commit === undefined) throw new Error("missing commit " + String(index));
  return commit;
}

function makeRecord(commit: GitCommit, classification: ProbeClassification, index: number): ProbeRecord {
  const exitCode = classification === "pass" ? 0 : classification === "fail" ? 1 : null;
  return {
    sha: commit.sha,
    shortSha: commit.shortSha,
    subject: commit.subject,
    classification,
    exitCode,
    signal: null,
    timedOut: false,
    durationMs: 1,
    checkoutMs: 0,
    command: "probe " + String(index),
    startedAt: "2026-01-01T00:00:00.000Z",
    logExcerpt: "probe " + String(index),
    failingStep: "step",
    jobConclusion: "",
    runId: "",
    runUrl: "",
    notes: [],
  };
}

describe("runBisect", () => {
  test("finds the first failing commit in a linear chain", async () => {
    const range = makeRange(17);
    const firstBadIndex = 7;
    const calls: number[] = [];
    const probe: CommitProbe = async (commit, index) => {
      calls.push(index);
      return makeRecord(commit, index >= firstBadIndex ? "fail" : "pass", index);
    };
    const outcome = await runBisect(range, probe);
    expect(outcome.kind).toBe("found");
    if (outcome.kind !== "found") return;
    expect(outcome.result.firstBad.sha).toBe(commitAt(range, firstBadIndex).sha);
    expect(outcome.result.lastGood.sha).toBe(commitAt(range, firstBadIndex - 1).sha);
    expect(outcome.result.steps).toBe(4);
    expect(outcome.result.probes.length).toBe(6);
    expect(calls[0]).toBe(0);
    expect(calls[1]).toBe(16);
  });

  test("refuses when last-green does not pass", async () => {
    const range = makeRange(8);
    const probe: CommitProbe = async (commit, index) => makeRecord(commit, "fail", index);
    const outcome = await runBisect(range, probe);
    expect(outcome.kind).toBe("refused");
    if (outcome.kind !== "refused") return;
    expect(outcome.exitCode).toBe(3);
    expect(outcome.reason).toContain("last-green");
    expect(outcome.probes.length).toBe(1);
  });

  test("refuses when red passes", async () => {
    const range = makeRange(8);
    const probe: CommitProbe = async (commit, index) => makeRecord(commit, "pass", index);
    const outcome = await runBisect(range, probe);
    expect(outcome.kind).toBe("refused");
    if (outcome.kind !== "refused") return;
    expect(outcome.exitCode).toBe(3);
    expect(outcome.reason).toContain("does not reproduce");
    expect(outcome.probes.length).toBe(2);
  });

  test("refuses when a probe cannot complete", async () => {
    const range = makeRange(17);
    const probe: CommitProbe = async (commit, index) => {
      if (index === 8) return makeRecord(commit, "error", index);
      return makeRecord(commit, index >= 7 ? "fail" : "pass", index);
    };
    const outcome = await runBisect(range, probe);
    expect(outcome.kind).toBe("refused");
    if (outcome.kind !== "refused") return;
    expect(outcome.exitCode).toBe(3);
    expect(outcome.reason).toContain("could not complete");
    expect(outcome.probes.length).toBe(3);
  });

  test("reports red as the first bad commit when the range has one step", async () => {
    const range = makeRange(2);
    const probe: CommitProbe = async (commit, index) =>
      makeRecord(commit, index === 0 ? "pass" : "fail", index);
    const outcome = await runBisect(range, probe);
    expect(outcome.kind).toBe("found");
    if (outcome.kind !== "found") return;
    expect(outcome.result.firstBad.sha).toBe(commitAt(range, 1).sha);
    expect(outcome.result.steps).toBe(0);
    expect(outcome.result.probes.length).toBe(2);
  });
});

type FakeState = {
  firstBad: number;
  active: Set<string>;
  pushed: string[];
  deleted: string[];
  throwAt: number | null;
  failDelete: boolean;
};

function createState(firstBad: number): FakeState {
  return { firstBad, active: new Set<string>(), pushed: [], deleted: [], throwAt: null, failDelete: false };
}

function fakeBackend(state: FakeState): CiBackend {
  const indexBySha = new Map<string, number>();
  for (let index = 0; index < 64; index += 1) indexBySha.set(makeCommit(index).sha, index);
  return {
    push: async (sha: string, branch: string) => {
      const index = indexBySha.get(sha);
      if (index === undefined) throw new Error("unknown sha");
      state.active.add(branch);
      state.pushed.push(branch);
    },
    dispatch: async () => {
      return;
    },
    wait: async (sha: string): Promise<CiRun> => {
      const index = indexBySha.get(sha);
      if (index === undefined) throw new Error("unknown sha");
      if (state.throwAt === index) throw new Error("wait failed");
      const failure = index >= state.firstBad;
      const conclusion = failure ? "failure" : "success";
      return {
        runId: "run-" + String(index),
        runUrl: "https://example.invalid/run/" + String(index),
        job: {
          databaseId: "job-1",
          name: "linux",
          conclusion,
          steps: [{ name: "compile", conclusion: failure ? "failure" : "success" }],
        },
      };
    },
    log: async (runId: string) => "log for " + runId,
    list: async (prefix: string) => Array.from(state.active).filter((branch) => branch.startsWith(prefix)),
    delete: async (branch: string) => {
      if (state.failDelete) throw new Error("delete refused");
      state.active.delete(branch);
      state.deleted.push(branch);
    },
  };
}

const ciOptions: CiProbeOptions = {
  repoRoot: "/repo",
  workflow: "ci.yml",
  job: "linux",
  remote: "origin",
  gh: "gh",
  pollMs: 1,
  timeoutMs: 1000,
  retryDelayMs: 1,
  logLines: 5,
  keepBranches: false,
};

describe("ci probe cleanup", () => {
  test("deletes every pushed temporary branch", async () => {
    const range = makeRange(17);
    const state = createState(7);
    const ci = createCiProbe(ciOptions, fakeBackend(state));
    const outcome = await runBisect(range, ci.probe);
    const cleanup = await ci.cleanup();
    expect(outcome.kind).toBe("found");
    expect(state.pushed.length).toBe(6);
    expect(state.deleted.length).toBe(state.pushed.length);
    expect(state.active.size).toBe(0);
    expect(cleanup.failures).toEqual([]);
  });

  test("deletes the branch when the CI wait throws", async () => {
    const range = makeRange(17);
    const state = createState(7);
    state.throwAt = 8;
    const ci = createCiProbe(ciOptions, fakeBackend(state));
    const outcome = await runBisect(range, ci.probe);
    const cleanup = await ci.cleanup();
    expect(outcome.kind).toBe("refused");
    expect(state.pushed.length).toBe(3);
    expect(state.active.size).toBe(0);
    expect(cleanup.failures).toEqual([]);
  });

  test("keeps the branch when deletion is refused and reports the failure", async () => {
    const range = makeRange(2);
    const state = createState(1);
    state.failDelete = true;
    const ci = createCiProbe(ciOptions, fakeBackend(state));
    const outcome = await runBisect(range, ci.probe);
    const cleanup = await ci.cleanup();
    expect(outcome.kind).toBe("found");
    expect(state.pushed.length).toBe(2);
    expect(state.active.size).toBe(2);
    expect(cleanup.failures.length).toBeGreaterThan(0);
  });
});

type Ancestry = {
  forward: boolean;
  backward: boolean;
  firstParent: boolean;
};

function fakeResult(code: number, stdout: string, stderr = ""): ProcessResult {
  return { code, signal: null, timedOut: false, durationMs: 0, stdout, stderr, stdoutBytes: null, truncated: false };
}

function fakeRunner(ancestry: Ancestry): GitRunner {
  return async (_repo: string, args: string[]) => {
    if (args[0] === "rev-parse" && args[1] === "--show-toplevel") return fakeResult(0, "/repo\n");
    if (args[0] === "rev-parse" && args[1] === "--verify") {
      const revision = (args[3] ?? "").replace(/\^\{\w+\}$/, "");
      const sha = revision === "aaa" ? "a".repeat(40) : revision === "bbb" ? "b".repeat(40) : "";
      return fakeResult(sha.length > 0 ? 0 : 1, sha.length > 0 ? sha + "\n" : "");
    }
    if (args[0] === "merge-base" && args[1] === "--is-ancestor") {
      const ancestor = args[2] ?? "";
      const descendant = args[3] ?? "";
      if (ancestor === "a".repeat(40) && descendant === "b".repeat(40)) {
        return fakeResult(ancestry.forward ? 0 : 1, "");
      }
      if (ancestor === "b".repeat(40) && descendant === "a".repeat(40)) {
        return fakeResult(ancestry.backward ? 0 : 1, "");
      }
      return fakeResult(1, "");
    }
    if (args[0] === "log" && args[1] === "--first-parent" && args[2] === "--format=%H") {
      return fakeResult(0, ancestry.firstParent ? "a".repeat(40) + "\n" + "b".repeat(40) + "\n" : "b".repeat(40) + "\n");
    }
    return fakeResult(1, "", "unexpected git command");
  };
}

describe("resolveGitRange", () => {
  test("rejects two commits that are not on one chain", async () => {
    const range = resolveGitRange("/repo", "aaa", "bbb", fakeRunner({ forward: false, backward: false, firstParent: false }));
    await expect(range).rejects.toBeInstanceOf(AttributionRangeError);
    await expect(range).rejects.toThrow("not on one ancestry chain");
  });

  test("rejects a reversed range", async () => {
    const range = resolveGitRange("/repo", "aaa", "bbb", fakeRunner({ forward: false, backward: true, firstParent: false }));
    await expect(range).rejects.toBeInstanceOf(AttributionRangeError);
    await expect(range).rejects.toThrow("descendant");
  });

  test("rejects a last-green commit outside the first-parent chain", async () => {
    const range = resolveGitRange("/repo", "aaa", "bbb", fakeRunner({ forward: true, backward: false, firstParent: false }));
    await expect(range).rejects.toBeInstanceOf(AttributionRangeError);
    await expect(range).rejects.toThrow("first-parent chain");
  });
});

describe("parseArgs", () => {
  test("reads both flag forms and keeps defaults", () => {
    const options = parseArgs(["--repo=/r", "--last-green", "aaa", "--red", "bbb", "--command", "bun test"]);
    expect(options.repo).toBe("/r");
    expect(options.mode).toBe("local");
    expect(options.materialize).toBe("worktree");
    expect(options.timeoutMs).toBe(1800000);
    expect(options.command).toBe("bun test");
  });

  test("requires workflow and job in ci mode", () => {
    expect(() => parseArgs(["--repo", "/r", "--last-green", "aaa", "--red", "bbb", "--mode", "ci"])).toThrow(UsageError);
  });

  test("rejects a non-positive timeout", () => {
    expect(() => parseArgs([
      "--repo", "/r", "--last-green", "aaa", "--red", "bbb", "--command", "x", "--timeout-ms", "0",
    ])).toThrow(UsageError);
  });

  test("rejects an unknown option", () => {
    expect(() => parseArgs(["--bogus"])).toThrow(UsageError);
  });
});
