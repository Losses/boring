import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

type TestRecord = { id: string; verdict: string };
type CommandResult = { code: number; output: string };

const targets = ["haxe", "ts", "kotlin", "rust", "swift", "dart"];
const expected = ["tests.DriverPlanTests.hostPlatform", "tests.DriverPlanTests.parse", "tests.DriverPlanTests.generation", "tests.DriverPlanTests.swiftLibrary", "tests.DriverPlanTests.invalidConfig", "tests.DriverPlanTests.comparison", "tests.DriverPlanTests.testCommands", "tests.DriverPlanTests.packAndEnvironment"];
const resultsDir = mkdtempSync(join(tmpdir(), "boring-driver-probes-"));
const projectFile = resolve(`.driver-probes-${process.pid}.json`);
const projectText = readFileSync("boring.json", "utf8").split("\n")
  .filter((line) => !line.trimStart().startsWith("//")).join("\n");
const project = JSON.parse(projectText) as Record<string, unknown>;
project.resultsDir = resultsDir;
writeFileSync(projectFile, JSON.stringify(project));

function run(args: string[]): CommandResult {
  const result = Bun.spawnSync(["boring", ...args], {
    cwd: resolve("."),
    env: { ...process.env, BORING_EXPECT_PLATFORM: process.platform },
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: result.exitCode,
    output: result.stdout.toString() + result.stderr.toString(),
  };
}

try {
  for (const target of targets) {
    const results = join(resultsDir, `${target}.jsonl`);
    for (const action of ["gen", "test"]) {
      const result = run([action, target, "--project", projectFile]);
      if (result.code !== 0) {
        throw new Error(`driver ${action} ${target} failed:\n${result.output}`);
      }
    }
    const records = readFileSync(results, "utf8")
      .split("\n")
      .filter((line) => line.length > 0)
      .map((line): TestRecord => JSON.parse(line) as TestRecord);
    for (const id of expected) {
      const record = records.find((item) => item.id === id);
      if (record?.verdict !== "pass") {
        throw new Error(`${target}: ${id} produced ${record?.verdict ?? "no result"}`);
      }
    }
    process.stdout.write(`${target}: ${expected.length} driver probes passed\n`);
  }
} finally {
  rmSync(projectFile, { force: true });
  rmSync(resultsDir, { recursive: true, force: true });
}
