// Driver probe runner: the execution half of the cross-target driver probe.
//
// Boundary (packages/test/README.md): bin/ drives one test run (process
// orchestration, cross-target scheduling) and never decides a verdict. The
// assertions live in tests/driver/cross-target.ts; this module only knows how
// to run the boring driver for one target/action and hand back results.
//
// Runnable standalone inside nix develop without the repository-root
// package.json:
//   bun packages/test/bin/driver-probe-runner.ts
// It resolves the repository root from its own path, so the caller's cwd does
// not matter.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export type TestRecord = { id: string; verdict: string };
export type CommandResult = { code: number; output: string };

const here = dirname(fileURLToPath(import.meta.url));
export const repoRoot = resolve(here, "..", "..", "..");

export function runBoring(args: string[], cwd = repoRoot): CommandResult {
  const result = Bun.spawnSync(["boring", ...args], {
    cwd,
    env: { ...process.env, BORING_EXPECT_PLATFORM: process.platform },
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: result.exitCode,
    output: result.stdout.toString() + result.stderr.toString(),
  };
}

export type ProbeSession = {
  resultsDir: string;
  projectFile: string;
  readResults: (target: string) => TestRecord[];
  close: () => void;
};

// Materialize the probe project: a copy of boring.json with a fresh,
// pid-unique results directory, written next to the caller's cwd.
export function openProbeSession(cwd = repoRoot): ProbeSession {
  const resultsDir = mkdtempSync(join(tmpdir(), "boring-driver-probes-"));
  const projectFile = resolve(cwd, `.driver-probes-${process.pid}.json`);
  const projectText = readFileSync(join(repoRoot, "boring.json"), "utf8")
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("//")).join("\n");
  const project = JSON.parse(projectText) as Record<string, unknown>;
  project.resultsDir = resultsDir;
  writeFileSync(projectFile, JSON.stringify(project));
  return {
    resultsDir,
    projectFile,
    readResults(target: string): TestRecord[] {
      return readFileSync(join(resultsDir, `${target}.jsonl`), "utf8")
        .split("\n")
        .filter((line) => line.length > 0)
        .map((line) => JSON.parse(line) as TestRecord);
    },
    close(): void {
      rmSync(projectFile, { force: true });
      rmSync(resultsDir, { recursive: true, force: true });
    },
  };
}

if (import.meta.main) {
  console.log("driver-probe-runner: library entry; import it from the owning test file.");
  console.log("repo root: " + repoRoot);
}
