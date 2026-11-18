// Binary search over a validated first-parent chain.

import type {
  BisectOutcome,
  BisectRefused,
  CommitProbe,
  GitCommit,
  GitRange,
  ProbeRecord,
} from "./types.ts";

function shortSha(commit: GitCommit): string {
  return commit.shortSha;
}

function refuse(reason: string, exitCode: number, probes: ProbeRecord[]): BisectRefused {
  return { kind: "refused", reason, exitCode, probes };
}

export async function runBisect(range: GitRange, probe: CommitProbe): Promise<BisectOutcome> {
  const commits = range.commits;
  const lastIndex = commits.length - 1;
  const cache = new Map<string, ProbeRecord>();
  const probes: ProbeRecord[] = [];

  async function probeAt(index: number): Promise<ProbeRecord> {
    const commit = commits[index];
    if (commit === undefined) throw new Error("commit index " + String(index) + " is outside the range");
    const cached = cache.get(commit.sha);
    if (cached !== undefined) return cached;
    const record = await probe(commit, index);
    cache.set(commit.sha, record);
    probes.push(record);
    return record;
  }

  const boundaryGreen = await probeAt(0);
  if (boundaryGreen.classification !== "pass") {
    const detail = boundaryGreen.classification === "fail"
      ? "exited " + String(boundaryGreen.exitCode)
      : "could not complete";
    return refuse(
      "last-green " + shortSha(commits[0] as GitCommit) + " " + detail +
        "; the range or the probe command is wrong",
      3,
      probes,
    );
  }

  const boundaryRed = await probeAt(lastIndex);
  if (boundaryRed.classification === "pass") {
    return refuse(
      "the failure does not reproduce at red " + shortSha(commits[lastIndex] as GitCommit) +
        "; refusing to attribute a commit",
      3,
      probes,
    );
  }
  if (boundaryRed.classification === "error") {
    return refuse(
      "the probe of red " + shortSha(commits[lastIndex] as GitCommit) +
        " could not complete; refusing to attribute a commit",
      3,
      probes,
    );
  }

  let low = 0;
  let high = lastIndex;
  let steps = 0;
  while (high - low > 1) {
    const mid = Math.floor((low + high) / 2);
    if (mid === low || mid === high) break;
    steps += 1;
    const record = await probeAt(mid);
    if (record.classification === "error") {
      return refuse(
        "the probe of " + record.sha.slice(0, 10) + " could not complete; refusing to attribute a commit",
        3,
        probes,
      );
    }
    if (record.classification === "fail") {
      high = mid;
    } else {
      low = mid;
    }
  }

  const firstBad = commits[high];
  const lastGood = commits[low];
  if (firstBad === undefined || lastGood === undefined) {
    return refuse("the bisect did not converge on a commit", 1, probes);
  }
  return {
    kind: "found",
    result: { firstBad, lastGood, probes, steps },
  };
}
