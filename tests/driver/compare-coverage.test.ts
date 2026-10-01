import { afterEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const entry = resolve("out/driver/driver.js");
const dirs: string[] = [];
type CompareResult = { code: number; output: string };

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function project(): string {
  const dir = mkdtempSync(join(tmpdir(), "boring-coverage-"));
  dirs.push(dir);
  mkdirSync(join(dir, "out", "results"), { recursive: true });
  writeFileSync(join(dir, "boring.json"), JSON.stringify({
    outRoot: "out", resultsDir: "out/results", baseline: "reference", sourceRoots: [],
    bundles: [{ id: "reference", target: "ts" }],
  }));
  writeFileSync(join(dir, "out", "results", "reference.jsonl"),
    '{"id":"probe","name":"probe","verdict":"pass"}\n');
  return dir;
}

function compare(dir: string): CompareResult {
  const result = Bun.spawnSync([process.execPath, entry, "compare", "--project", join(dir, "boring.json")], {
    cwd: dir, stdout: "pipe", stderr: "pipe",
  });
  return { code: result.exitCode, output: result.stdout.toString() + result.stderr.toString() };
}

test("a consumer comparison skips repository mechanism coverage", () => {
  const result = compare(project());
  expect(result.code).toBe(0);
  expect(result.output).toContain("Mechanism coverage: skipped");
});

test("a project mechanism declaration enforces coverage", () => {
  const dir = project();
  const marker = join(dir, "tools", "test-consistency");
  mkdirSync(marker, { recursive: true });
  writeFileSync(join(marker, "mechanism-coverage.json"),
    JSON.stringify({ covered: [], uncoveredAllowlist: [] }));
  const result = compare(dir);
  expect(result.code).toBe(1);
  expect(result.output).toContain("ComparatorPlan is missing from coverage data");
});

test("a malformed mechanism declaration reports its path", () => {
  const dir = project();
  const marker = join(dir, "tools", "test-consistency");
  mkdirSync(marker, { recursive: true });
  writeFileSync(join(marker, "mechanism-coverage.json"), "{bad");
  const result = compare(dir);
  expect(result.code).toBe(1);
  expect(result.output).toContain("Invalid mechanism coverage file:");
  expect(result.output).toContain(join(marker, "mechanism-coverage.json"));
});
