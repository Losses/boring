/**
 * The `_redirects` writer (spec 26 ruling 9). Three rule forms exist:
 * one universal Swift rule mapping every zip request to the archive
 * base, one dynamic rule per cargo crate, and one dynamic rule per
 * Maven artifact. A dynamic rule is emitted only when every version of
 * that package lives in one repository and is tagged `v<version>`; any
 * deviation falls back to exact static rules, one per version and, for
 * Maven, per file. Cargo rules are emitted in descending crate-name
 * length order because matching is first-match-wins and a shorter name
 * would capture a longer crate's requests. The tool counts dynamic and
 * static rules and stops when the registry would exceed the host cap.
 */

import { compareSemver } from "./semver.ts";

/** One cargo rule input: one version of one crate. */
export type CargoRuleInput = {
  repo: string;
  tag: string;
  name: string;
  version: string;
  artifact: string;
  url: string;
};

/** One file of a Maven rule input: the file name and its asset URL. */
export type MavenRuleFile = { file: string; url: string };

/** One Maven rule input: one version of one artifact with its files. */
export type MavenRuleInput = {
  repo: string;
  tag: string;
  name: string;
  version: string;
  groupId: string;
  files: MavenRuleFile[];
};

/** One Swift rewrite input: the package, plus the version when the rule serves a version document. */
export type SwiftRuleInput = {
  scope: string;
  name: string;
  version?: string;
};

export type RedirectInputs = {
  archiveBase?: string;
  swift: SwiftRuleInput[];
  cargo: CargoRuleInput[];
  maven: MavenRuleInput[];
};

/**
 * Derives the destination prefix of one asset URL: everything before
 * `<tag>/<file>`. A GitHub listing yields the
 * `https://github.com/<owner>/<repo>/releases/download/` prefix the
 * specification shows, because the URL is recorded verbatim from the
 * listing; a test fixture yields the fixture origin. Returns undefined
 * when the URL does not end with `<tag>/<file>`.
 */
function urlPrefix(url: string, tag: string, file: string): string | undefined {
  const tail = `${tag}/${file}`;
  if (!url.endsWith(tail)) {
    return undefined;
  }
  return url.slice(0, url.length - tail.length);
}

/** One version entry of a rule-input group: the release tag, the version, the repository. */
type VersionEntry = { tag: string; version: string; repo: string };

/** One asset whose URL the prefix derivation reads. */
type UrlEntry = { url: string; tag: string; file: string };

function groupByUrlPrefixes(entries: VersionEntry[], urls: UrlEntry[]): string | undefined {
  const repos = new Set(entries.map((entry) => entry.repo));
  if (repos.size !== 1) {
    return undefined;
  }
  for (const entry of entries) {
    if (entry.tag !== `v${entry.version}`) {
      return undefined;
    }
  }
  const prefixes = new Set<string>();
  for (const asset of urls) {
    const prefix = urlPrefix(asset.url, asset.tag, asset.file);
    if (prefix === undefined) {
      return undefined;
    }
    prefixes.add(prefix);
  }
  if (prefixes.size !== 1) {
    return undefined;
  }
  return prefixes.values().next().value;
}

function cargoLines(cargo: CargoRuleInput[]): string[] {
  const byName = new Map<string, CargoRuleInput[]>();
  for (const entry of cargo) {
    const group = byName.get(entry.name) ?? [];
    group.push(entry);
    byName.set(entry.name, group);
  }
  const names = [...byName.keys()].sort((a, b) => b.length - a.length || (a < b ? -1 : 1));
  const lines: string[] = [];
  for (const name of names) {
    const group = (byName.get(name) ?? []).slice().sort((a, b) => compareSemver(a.version, b.version));
    const template = group.every(
      (entry) => entry.artifact === `${entry.name}-${entry.version}.crate`,
    )
      ? groupByUrlPrefixes(
          group,
          group.map((entry) => ({ url: entry.url, tag: entry.tag, file: entry.artifact })),
        )
      : undefined;
    if (template !== undefined) {
      lines.push(
        `/cargo/dl/${name}-:version.crate  ${template}v:version/${name}-:version.crate  302`,
      );
    } else {
      for (const entry of group) {
        lines.push(`/cargo/dl/${entry.name}-${entry.version}.crate  ${entry.url}  302`);
      }
    }
  }
  return lines;
}

function mavenLines(maven: MavenRuleInput[]): string[] {
  const byArtifact = new Map<string, MavenRuleInput[]>();
  for (const entry of maven) {
    const key = `${entry.groupId}/${entry.name}`;
    const group = byArtifact.get(key) ?? [];
    group.push(entry);
    byArtifact.set(key, group);
  }
  const keys = [...byArtifact.keys()].sort((a, b) => (a < b ? -1 : 1));
  const lines: string[] = [];
  for (const key of keys) {
    const group = (byArtifact.get(key) ?? []).slice().sort((a, b) => compareSemver(a.version, b.version));
    const template = groupByUrlPrefixes(
      group,
      group.flatMap((entry) =>
        entry.files.map((asset) => ({ url: asset.url, tag: entry.tag, file: asset.file })),
      ),
    );
    const first = group[0];
    if (template !== undefined && first) {
      const groupPath = first.groupId.replaceAll(".", "/");
      lines.push(`/maven/${groupPath}/${first.name}/:version/:file  ${template}v:version/:file  302`);
    } else {
      for (const entry of group) {
        const groupPath = entry.groupId.replaceAll(".", "/");
        for (const asset of entry.files) {
          lines.push(
            `/maven/${groupPath}/${entry.name}/${entry.version}/${asset.file}  ${asset.url}  302`,
          );
        }
      }
    }
  }
  return lines;
}

/**
 * Builds the `_redirects` lines. The universal Swift zip rule comes
 * first; then one exact 200 rewrite per Swift package and per version,
 * serving the JSON documents stored with a `.json` extension at their
 * extensionless protocol paths; then the cargo rules in descending
 * name length; then the Maven rules ordered by group path and name.
 * The Swift rules are emitted whenever an archive base is known, so a
 * registry without Swift packages omits them.
 */
export function buildRedirectLines(inputs: RedirectInputs): string[] {
  const lines: string[] = [];
  if (inputs.archiveBase !== undefined) {
    lines.push(
      `/swift/:scope/:name/*.zip  ${inputs.archiveBase}/swift/:scope/:name/:splat.zip  303`,
    );
    for (const entry of inputs.swift) {
      const base = `/swift/${entry.scope}/${entry.name}`;
      lines.push(entry.version === undefined
        ? `${base}  ${base}.json  200`
        : `${base}/${entry.version}  ${base}/${entry.version}.json  200`);
    }
  }
  lines.push(...cargoLines(inputs.cargo));
  lines.push(...mavenLines(inputs.maven));
  return lines;
}

/** The rule counts: a rule is dynamic when its source path carries a placeholder. */
export type RuleCounts = { dynamic: number; static: number; total: number };

/** Counts dynamic and static rules over the generated lines. */
export function countRules(lines: ReadonlyArray<string>): RuleCounts {
  let dynamic = 0;
  let staticCount = 0;
  for (const line of lines) {
    const source = line.split(/\s+/, 1)[0] ?? "";
    if (source.includes(":") || source.includes("*")) {
      dynamic += 1;
    } else {
      staticCount += 1;
    }
  }
  return { dynamic, static: staticCount, total: dynamic + staticCount };
}

const DYNAMIC_CAP = 100;
const STATIC_CAP = 2000;
const TOTAL_CAP = 2100;

/**
 * Stops the generation when the rule counts would exceed the host cap
 * (Cloudflare Pages: 100 dynamic, 2000 static, 2100 total), naming both
 * counts. The documented overflow path is Bulk Redirects or moving that
 * namespace to object storage.
 */
export function guardRuleCounts(counts: RuleCounts): void {
  if (counts.dynamic > DYNAMIC_CAP || counts.static > STATIC_CAP || counts.total > TOTAL_CAP) {
    throw new Error(
      `redirect rules exceed the host cap: ${counts.dynamic} dynamic, ${counts.static} static, ` +
        `${counts.total} total (caps ${DYNAMIC_CAP} dynamic, ${STATIC_CAP} static, ${TOTAL_CAP} total); ` +
        "the overflow path is Bulk Redirects or moving the namespace to object storage",
    );
  }
}
