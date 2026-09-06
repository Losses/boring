import { existsSync, readFileSync, writeFileSync } from "node:fs";

const scripts = [
  "gen:ts",
  "gen:kotlin",
  "gen:kotlin-f32",
  "gen:rust",
  "gen:rust-f32",
  "gen:swift",
  "gen:swift-f32",
  "gen:dart",
];
const baselinePath = "tools/perf/baseline.json";

function option(name: string): string | undefined {
  const index = Bun.argv.indexOf(name);
  return index >= 0 ? Bun.argv[index + 1] : undefined;
}

const mode = Bun.argv.includes("--write") ? "write" : Bun.argv.includes("--check") ? "check" : "";
const rounds = Number(option("--rounds") ?? "1");
if (!mode || !Number.isInteger(rounds) || rounds < 1) {
  console.error("Usage: bun tools/perf/measure.ts (--write|--check) [--rounds N]");
  process.exit(2);
}

function run(script: string): number {
  const start = Date.now();
  const result = Bun.spawnSync(["bun", "run", script], { stdout: "inherit", stderr: "inherit" });
  if (!result.success) {
    console.error(`Performance command failed: ${script}`);
    process.exit(result.exitCode || 1);
  }
  return Date.now() - start;
}

function median(values: number[]): number {
  values.sort((a, b) => a - b);
  const middle = Math.floor(values.length / 2);
  return values.length % 2 === 0 ? Math.round((values[middle - 1] + values[middle]) / 2) : values[middle];
}

const entries = scripts.map((script) => {
  const values = Array.from({ length: rounds }, () => run(script));
  const medianMs = median(values);
  console.log(`${script}: ${values.join(", ")} ms (median ${medianMs} ms)`);
  return { script, medianMs };
});
const result = { date: new Date().toISOString().slice(0, 10), rounds, entries };

if (mode === "write") {
  writeFileSync(baselinePath, JSON.stringify(result, null, 2) + "\n");
  console.log(`Wrote ${baselinePath}`);
} else {
  if (!existsSync(baselinePath)) {
    console.error(`Missing baseline: ${baselinePath}`);
    process.exit(1);
  }
  const baseline = JSON.parse(readFileSync(baselinePath, "utf8")) as typeof result;
  const regressions: string[] = [];
  for (const entry of entries) {
    const old = baseline.entries.find((candidate) => candidate.script === entry.script);
    if (!old) {
      regressions.push(`${entry.script}: missing from baseline`);
      continue;
    }
    if (entry.medianMs > old.medianMs * 1.05) {
      regressions.push(`${entry.script}: baseline ${old.medianMs} ms, current ${entry.medianMs} ms`);
    }
  }
  if (regressions.length > 0) {
    console.error(`Performance regression (over 5%):\n${regressions.map((line) => `  ${line}`).join("\n")}`);
    process.exit(1);
  }
  console.log("Performance baseline check passed.");
}
