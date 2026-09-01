/**
 * The command-line entry (spec 26). Parses the flags, validates what
 * validation happens before any network call, runs the release scan,
 * and writes the site. Every rejection prints its message to stderr
 * and exits 1.
 */

import * as fs from "node:fs";
import { scanReleases } from "./github.ts";
import { generateSite } from "./site.ts";

type Flags = {
  repos?: string;
  output?: string;
  baseUrl?: string;
  swiftScope?: string;
  archiveBase?: string;
  apiBase?: string;
  token?: string;
  cache?: string;
};

const USAGE =
  "usage: generate --repos <file> --output <site> --base-url <url> " +
  "[--swift-scope <scope>] [--archive-base <url>] [--api-base <url>] " +
  "[--token <token>] [--cache <dir>]";

function parseFlags(argv: string[]): Flags {
  const flags: Flags = {};
  const keys: ReadonlyArray<keyof Flags> = [
    "repos",
    "output",
    "baseUrl",
    "swiftScope",
    "archiveBase",
    "apiBase",
    "token",
    "cache",
  ];
  for (let index = 2; index < argv.length; index += 2) {
    const name = argv[index] ?? "";
    const value = argv[index + 1];
    if (!name.startsWith("--") || value === undefined) {
      throw new Error(USAGE);
    }
    const key = name.slice(2).replace(/-([a-z])/g, (_, letter: string) =>
      letter.toUpperCase(),
    ) as keyof Flags;
    if (!keys.includes(key)) {
      throw new Error(`unknown flag ${name}\n${USAGE}`);
    }
    flags[key] = value;
  }
  return flags;
}

function requireFlag(flags: Flags, key: keyof Flags, label: string): string {
  const value = flags[key];
  if (value === undefined || value.length === 0) {
    throw new Error(`${label} is required\n${USAGE}`);
  }
  return value;
}

/** Rejects a URL without an `http` or `https` scheme and strips a trailing slash. */
function normalizeOrigin(raw: string, label: string): string {
  const url = raw.endsWith("/") ? raw.slice(0, -1) : raw;
  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    throw new Error(`${label} ${raw} must start with http:// or https://`);
  }
  return url;
}

function readRepos(path: string): string[] {
  let text: string;
  try {
    text = fs.readFileSync(path, "utf8");
  } catch {
    throw new Error(`cannot read the repository list ${path}`);
  }
  const repos: string[] = [];
  for (const line of text.split("\n")) {
    const entry = line.trim();
    if (entry.length === 0 || entry.startsWith("#")) {
      continue;
    }
    repos.push(entry);
  }
  if (repos.length === 0) {
    throw new Error(`the repository list ${path} holds no entry`);
  }
  return repos;
}

function checkOutput(path: string): void {
  if (!fs.existsSync(path)) {
    return;
  }
  if (!fs.statSync(path).isDirectory()) {
    throw new Error(`the output path ${path} is not a directory`);
  }
  if (fs.readdirSync(path).length > 0) {
    throw new Error(`the output directory ${path} is not empty`);
  }
}

async function main(): Promise<void> {
  const flags = parseFlags(process.argv);
  const reposPath = requireFlag(flags, "repos", "--repos");
  const output = requireFlag(flags, "output", "--output");
  const baseUrl = normalizeOrigin(requireFlag(flags, "baseUrl", "--base-url"), "base URL");
  const apiBase = flags.apiBase === undefined
    ? "https://api.github.com"
    : normalizeOrigin(flags.apiBase, "API base");
  const archiveBase = flags.archiveBase === undefined
    ? undefined
    : normalizeOrigin(flags.archiveBase, "archive base");
  const token = flags.token ?? process.env.GITHUB_TOKEN;
  if (token === undefined || token.length === 0) {
    throw new Error("the scan requires a token: pass --token or set GITHUB_TOKEN");
  }
  const repos = readRepos(reposPath);
  checkOutput(output);
  const releases = await scanReleases({
    apiBase,
    repos,
    token,
    cacheDir: flags.cache,
  });
  generateSite(releases, {
    root: output,
    baseUrl,
    swiftScope: flags.swiftScope,
    archiveBase,
  });
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
