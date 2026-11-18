// Command line parsing for the attribution bisect tool.

import type { AttributionMode, MaterializeMode } from "./types.ts";

export class UsageError extends Error {
  readonly exitCode: number;

  constructor(message: string) {
    super(message);
    this.name = "UsageError";
    this.exitCode = 2;
  }
}

export type CliOptions = {
  repo: string;
  lastGreen: string;
  red: string;
  workflow: string;
  job: string;
  command: string;
  mode: AttributionMode;
  materialize: MaterializeMode;
  stepLabel: string;
  timeoutMs: number;
  ciTimeoutMs: number;
  pollMs: number;
  logLines: number;
  jsonPath: string;
  remote: string;
  gh: string;
  keepBranches: boolean;
  keepCheckout: boolean;
  help: boolean;
};

const VALUE_FLAGS: ReadonlySet<string> = new Set([
  "--repo",
  "--last-green",
  "--red",
  "--workflow",
  "--job",
  "--command",
  "--mode",
  "--materialize",
  "--step",
  "--timeout-ms",
  "--ci-timeout-ms",
  "--poll-ms",
  "--log-lines",
  "--json",
  "--remote",
  "--gh",
]);

const BOOLEAN_FLAGS: ReadonlySet<string> = new Set([
  "--help",
  "--keep-branches",
  "--keep-checkout",
]);

function parsePositiveInteger(name: string, raw: string, minimum: number): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value < minimum) {
    throw new UsageError(name + " expects an integer of at least " + String(minimum) + ", got " + raw);
  }
  return value;
}

function parseMode(raw: string): AttributionMode {
  if (raw === "local" || raw === "ci") return raw;
  throw new UsageError("--mode expects local or ci, got " + raw);
}

function parseMaterialize(raw: string): MaterializeMode {
  if (raw === "export" || raw === "worktree") return raw;
  throw new UsageError("--materialize expects export or worktree, got " + raw);
}

export function parseArgs(argv: string[]): CliOptions {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === undefined) continue;
    if (!argument.startsWith("--")) {
      throw new UsageError("unexpected positional argument " + argument);
    }
    const equals = argument.indexOf("=");
    const name = equals >= 0 ? argument.slice(0, equals) : argument;
    if (BOOLEAN_FLAGS.has(name)) {
      if (equals >= 0) throw new UsageError(name + " does not take a value");
      flags.add(name);
      continue;
    }
    if (!VALUE_FLAGS.has(name)) {
      throw new UsageError("unknown option " + name);
    }
    let value: string;
    if (equals >= 0) {
      value = argument.slice(equals + 1);
    } else {
      const next = argv[index + 1];
      if (next === undefined) throw new UsageError(name + " expects a value");
      value = next;
      index += 1;
    }
    values.set(name, value);
  }

  const help = flags.has("--help");
  const repo = values.get("--repo") ?? "";
  const lastGreen = values.get("--last-green") ?? "";
  const red = values.get("--red") ?? "";
  const mode = parseMode(values.get("--mode") ?? "local");
  const materialize = parseMaterialize(values.get("--materialize") ?? "worktree");
  const command = values.get("--command") ?? "";
  const workflow = values.get("--workflow") ?? "";
  const job = values.get("--job") ?? "";

  if (!help) {
    if (repo.length === 0) throw new UsageError("--repo is required");
    if (lastGreen.length === 0) throw new UsageError("--last-green is required");
    if (red.length === 0) throw new UsageError("--red is required");
    if (mode === "local" && command.length === 0) {
      throw new UsageError("--command is required in local mode");
    }
    if (mode === "ci" && workflow.length === 0) {
      throw new UsageError("--workflow is required in ci mode");
    }
    if (mode === "ci" && job.length === 0) {
      throw new UsageError("--job is required in ci mode");
    }
  }

  return {
    repo,
    lastGreen,
    red,
    workflow,
    job,
    command,
    mode,
    materialize,
    stepLabel: values.get("--step") ?? "local command",
    timeoutMs: parsePositiveInteger("--timeout-ms", values.get("--timeout-ms") ?? "1800000", 1000),
    ciTimeoutMs: parsePositiveInteger("--ci-timeout-ms", values.get("--ci-timeout-ms") ?? "7200000", 1000),
    pollMs: parsePositiveInteger("--poll-ms", values.get("--poll-ms") ?? "15000", 1000),
    logLines: parsePositiveInteger("--log-lines", values.get("--log-lines") ?? "60", 1),
    jsonPath: values.get("--json") ?? "",
    remote: values.get("--remote") ?? "origin",
    gh: values.get("--gh") ?? "gh",
    keepBranches: flags.has("--keep-branches"),
    keepCheckout: flags.has("--keep-checkout"),
    help,
  };
}

export function usage(): string {
  return [
    "Usage:",
    "  bun tools/attribution/cli.ts --repo <path> --last-green <sha> --red <sha> --command <command> [options]",
    "  bun tools/attribution/cli.ts --repo <path> --last-green <sha> --red <sha> --mode ci --workflow <file> --job <name> [options]",
    "",
    "Options:",
    "  --mode local|ci          Probe mode. Default: local.",
    "  --materialize export|worktree",
    "                           Local checkout style. Default: worktree.",
    "  --command <command>      Repro command for local mode, run through bash -c.",
    "  --step <label>           Step label recorded in the report. Default: local command.",
    "  --workflow <file>        Workflow file or name for ci mode.",
    "  --job <name>             Job name to classify in ci mode.",
    "  --timeout-ms <n>         Per local probe timeout. Default: 1800000.",
    "  --ci-timeout-ms <n>      Per CI probe timeout. Default: 7200000.",
    "  --poll-ms <n>            CI poll interval. Default: 15000.",
    "  --log-lines <n>          Log lines kept per probe. Default: 60.",
    "  --json <path|->          Write the JSON report to a file, or to stdout with -.",
    "  --remote <name>          Git remote used by ci mode. Default: origin.",
    "  --gh <path>              gh executable. Default: gh.",
    "  --keep-branches          Retain temporary branches. Default: delete them.",
    "  --keep-checkout          Retain the local checkout for inspection.",
    "  --help                   Print this text.",
    "",
    "Exit codes: 0 report produced, 2 invalid input or range, 3 probe could not",
    "decide, 4 temporary branch cleanup failed, 1 internal error.",
  ].join("\n");
}
