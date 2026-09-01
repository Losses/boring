/**
 * The site writer (spec 26 rulings 1 through 10). One call turns the
 * scanned releases into the complete site directory: the npm packuments,
 * the cargo sparse index, the Swift registry documents, the Pub hosted
 * documents, the Maven metadata, and the `_headers` and `_redirects`
 * artifacts. The site is a function of its inputs: two runs over the
 * same inputs produce byte-identical trees.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { createHash } from "node:crypto";
import { assetUrl, type ScannedRelease } from "./github.ts";
import type { Manifest, MavenLane } from "./manifest.ts";
import {
  buildRedirectLines,
  countRules,
  guardRuleCounts,
  type CargoRuleInput,
  type MavenRuleInput,
  type SwiftRuleInput,
} from "./redirects.ts";
import { compareSemver, isPrerelease } from "./semver.ts";

/** The site generation inputs: the output root and the registry-level values. */
export type SiteOptions = {
  root: string;
  baseUrl: string;
  swiftScope?: string;
  archiveBase?: string;
};

const SWIFT_SCOPE = /^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/;

const HEADERS = [
  "/*",
  "  Content-Version: 1",
  "/swift/:scope/:name",
  "  Content-Type: application/json",
  "/swift/:scope/:name/:version",
  "  Content-Type: application/json",
  "/swift/:scope/:name/:version/Package.swift",
  "  Content-Type: text/x-swift",
  "/pub/api/packages/*",
  "  Content-Type: application/vnd.pub.v2+json",
  "/swift/identifiers",
  "  Content-Type: application/json",
  "",
].join("\n");

type LaneKey = "npm" | "cargo" | "pub" | "swift" | "maven";

/** One release's lane entry, carrying the lane data and the release context. */
type LaneEntry<T> = { release: ScannedRelease; lane: T };

function laneDigest(key: LaneKey, manifest: Manifest): string {
  switch (key) {
    case "npm":
      return manifest.npm?.sha512 ?? "";
    case "cargo":
      return manifest.cargo?.sha256 ?? "";
    case "pub":
      return manifest.pub?.sha256 ?? "";
    case "swift":
      return manifest.swift?.sha256 ?? "";
    case "maven":
      return (manifest.maven?.artifacts ?? []).join("\n");
  }
}

/**
 * Collects one lane's entries, resolving the identity rule of ruling 2:
 * two releases claiming the same ecosystem, name, and version with equal
 * digests become one entry; different digests stop the generation naming
 * both repositories and tags.
 */
/** Selects one lane out of a manifest, or undefined when the release does not ship it. */
type LaneSelector<T> = (manifest: Manifest) => T | undefined;

function laneEntries<T>(
  releases: ReadonlyArray<ScannedRelease>,
  key: LaneKey,
  select: LaneSelector<T>,
): LaneEntry<T>[] {
  const seen = new Map<string, LaneEntry<T>>();
  for (const release of releases) {
    const lane = select(release.manifest);
    if (lane === undefined) {
      continue;
    }
    const identity = `${key}:${release.manifest.name}@${release.manifest.version}`;
    const digest = laneDigest(key, release.manifest);
    const first = seen.get(identity);
    if (first) {
      if (laneDigest(key, first.release.manifest) !== digest) {
        throw new Error(
          `${key} package ${release.manifest.name} ${release.manifest.version}: ` +
            `${first.release.repo} release ${first.release.tag} and ` +
            `${release.repo} release ${release.tag} disagree on digests`,
        );
      }
      continue;
    }
    seen.set(identity, { release, lane });
  }
  return [...seen.values()];
}

function groupByName<T>(entries: LaneEntry<T>[]): Map<string, LaneEntry<T>[]> {
  const groups = new Map<string, LaneEntry<T>[]>();
  for (const entry of entries) {
    const name = entry.release.manifest.name;
    const group = groups.get(name) ?? [];
    group.push(entry);
    groups.set(name, group);
  }
  return groups;
}

function byVersion<T>(entries: LaneEntry<T>[], direction: 1 | -1): LaneEntry<T>[] {
  return entries.slice().sort((a, b) =>
    direction * compareSemver(a.release.manifest.version, b.release.manifest.version),
  );
}

/** The highest semver without a prerelease, or the highest semver when every version carries one. */
function latestVersion(versions: string[]): string {
  const stable = versions.filter((version) => !isPrerelease(version));
  const pool = stable.length > 0 ? stable : versions;
  return pool.reduce((best, version) => (compareSemver(version, best) > 0 ? version : best));
}

function writeFile(root: string, relative: string, data: string): void {
  const target = path.join(root, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, data);
}

/** Serializes one JSON document: two-space indent, LF, one trailing newline. */
function jsonText(value: unknown): string {
  return `${JSON.stringify(value, null, 2)}\n`;
}

/** The packument request path: the unscoped name, or the scoped name with the slash percent-encoded lowercase. */
function npmRequestPath(name: string): string {
  const slash = name.indexOf("/");
  if (slash < 0) {
    return name;
  }
  return `${name.slice(0, slash)}%2f${name.slice(slash + 1)}`;
}

function writeNpm(root: string, releases: ReadonlyArray<ScannedRelease>): void {
  for (const [name, group] of groupByName(laneEntries(releases, "npm", (m) => m.npm))) {
    const versions: Record<string, unknown> = {};
    for (const entry of byVersion(group, 1)) {
      const manifest = entry.release.manifest;
      const version: Record<string, unknown> = { name, version: manifest.version };
      if (manifest.license !== undefined) {
        version.license = manifest.license;
      }
      version.dist = {
        tarball: assetUrl(entry.release, entry.lane.artifact),
        integrity: `sha512-${entry.lane.sha512}`,
      };
      versions[manifest.version] = version;
    }
    const all = group.map((entry) => entry.release.manifest.version);
    const packument = { name, "dist-tags": { latest: latestVersion(all) }, versions };
    writeFile(root, path.join("npm", npmRequestPath(name)), jsonText(packument));
  }
}

/** The sparse prefix tier of one lowercased crate name. */
function cargoTier(name: string): string {
  if (name.length === 1) {
    return path.join("1", name);
  }
  if (name.length === 2) {
    return path.join("2", name);
  }
  if (name.length === 3) {
    return path.join("3", name.slice(0, 1), name);
  }
  return path.join(name.slice(0, 2), name.slice(2, 4), name);
}

function writeCargo(root: string, baseUrl: string, releases: ReadonlyArray<ScannedRelease>): CargoRuleInput[] {
  const entries = laneEntries(releases, "cargo", (m) => m.cargo);
  for (const entry of entries) {
    const name = entry.release.manifest.name;
    if (name !== name.toLowerCase()) {
      throw new Error(
        `${entry.release.repo} release ${entry.release.tag}: cargo name ${name} must be lowercase`,
      );
    }
  }
  writeFile(
    root,
    path.join("cargo", "index", "config.json"),
    jsonText({ dl: `${baseUrl}/cargo/dl/{crate}-{version}.crate` }),
  );
  for (const [name, group] of groupByName(entries)) {
    const lines = byVersion(group, 1).map((entry) => {
      const lane = entry.lane;
      return JSON.stringify({
        name,
        vers: entry.release.manifest.version,
        deps: [],
        cksum: lane.sha256,
        features: {},
        yanked: false,
        v: 2,
      });
    });
    writeFile(
      root,
      path.join("cargo", "index", cargoTier(name)),
      `${lines.join("\n")}\n`,
    );
  }
  return entries.map((entry) => ({
    repo: entry.release.repo,
    tag: entry.release.tag,
    name: entry.release.manifest.name,
    version: entry.release.manifest.version,
    artifact: entry.lane.artifact,
    url: assetUrl(entry.release, entry.lane.artifact),
  }));
}

function writeSwift(
  root: string,
  scope: string,
  releases: ReadonlyArray<ScannedRelease>,
): SwiftRuleInput[] {
  const rules: SwiftRuleInput[] = [];
  for (const [name, group] of groupByName(laneEntries(releases, "swift", (m) => m.swift))) {
    const ascending = byVersion(group, 1);
    const releaseDoc: Record<string, unknown> = {};
    for (const entry of ascending) {
      releaseDoc[entry.release.manifest.version] = {};
    }
    writeFile(root, path.join("swift", scope, `${name}.json`), jsonText({ releases: releaseDoc }));
    rules.push({ scope, name });
    for (const entry of ascending) {
      const lane = entry.lane;
      const version = entry.release.manifest.version;
      writeFile(
        root,
        path.join("swift", scope, name, `${version}.json`),
        jsonText({
          id: `${scope}.${name}`,
          version,
          resources: [{ name: "source-archive", type: "application/zip", checksum: lane.sha256 }],
          metadata: {},
        }),
      );
      rules.push({ scope, name, version });
      writeFile(root, path.join("swift", scope, name, version, "Package.swift"), lane.packageSwift);
    }
  }
  writeFile(root, path.join("swift", "identifiers"), jsonText([]));
  return rules;
}

function writePub(root: string, releases: ReadonlyArray<ScannedRelease>): void {
  for (const [name, group] of groupByName(laneEntries(releases, "pub", (m) => m.pub))) {
    const newest = byVersion(group, -1).map((entry) => {
      const lane = entry.lane;
      return {
        version: entry.release.manifest.version,
        archive_url: assetUrl(entry.release, lane.artifact),
        archive_sha256: lane.sha256,
        pubspec: lane.pubspec,
      };
    });
    const all = group.map((entry) => entry.release.manifest.version);
    writeFile(
      root,
      path.join("pub", "api", "packages", name),
      jsonText({ name, latest: latestVersion(all), versions: newest }),
    );
  }
}

function writeMaven(root: string, releases: ReadonlyArray<ScannedRelease>): MavenRuleInput[] {
  const entries = laneEntries(releases, "maven", (m) => m.maven);
  const groups = new Map<string, LaneEntry<MavenLane>[]>();
  for (const entry of entries) {
    const key = `${entry.lane.groupId}/${entry.release.manifest.name}`;
    const group = groups.get(key) ?? [];
    group.push(entry);
    groups.set(key, group);
  }
  for (const [, group] of [...groups.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
    const ascending = byVersion(group, 1);
    const first = ascending[0];
    if (!first) {
      continue;
    }
    const groupId = first.lane.groupId;
    const name = first.release.manifest.name;
    const versions = ascending.map((entry) => entry.release.manifest.version);
    const xml =
      `<?xml version="1.0" encoding="UTF-8"?>\n` +
      `<metadata>\n` +
      `  <groupId>${groupId}</groupId>\n` +
      `  <artifactId>${name}</artifactId>\n` +
      `  <versioning>\n` +
      `    <latest>${latestVersion(versions)}</latest>\n` +
      `    <release>${latestVersion(versions.filter((version) => !isPrerelease(version)))}</release>\n` +
      `    <versions>\n` +
      versions.map((version) => `      <version>${version}</version>`).join("\n") +
      `\n    </versions>\n` +
      `  </versioning>\n` +
      `</metadata>\n`;
    const groupPath = groupId.replaceAll(".", "/");
    const base = path.join("maven", groupPath, name);
    writeFile(root, `${base}/maven-metadata.xml`, xml);
    writeFile(root, `${base}/maven-metadata.xml.sha1`, `${createHash("sha1").update(xml).digest("hex")}\n`);
  }
  return entries.map((entry) => ({
    repo: entry.release.repo,
    tag: entry.release.tag,
    name: entry.release.manifest.name,
    version: entry.release.manifest.version,
    groupId: entry.lane.groupId,
    files: entry.lane.artifacts.map((file) => ({
      file,
      url: assetUrl(entry.release, file),
    })),
  }));
}

/**
 * Generates the complete site. Throws, naming the repository, release
 * tag, or path, on every rejection the command line section lists.
 */
export function generateSite(releases: ReadonlyArray<ScannedRelease>, options: SiteOptions): void {
  const swiftEntries = laneEntries(releases, "swift", (m) => m.swift);
  let scope = options.swiftScope;
  if (swiftEntries.length > 0 && scope === undefined) {
    throw new Error("a scanned release ships a Swift lane; --swift-scope is required");
  }
  if (scope !== undefined && !SWIFT_SCOPE.test(scope)) {
    throw new Error(`invalid Swift scope ${scope}`);
  }
  scope = scope ?? "";
  for (const entry of swiftEntries) {
    const manifest = entry.release.manifest;
    const lane = entry.lane;
    const expected = `swift/${scope}/${manifest.name}/${manifest.version}.zip`;
    if (lane.archive !== expected) {
      throw new Error(
        `${entry.release.repo} release ${entry.release.tag}: swift archive key ` +
          `${lane.archive} must equal ${expected}`,
      );
    }
  }
  fs.mkdirSync(options.root, { recursive: true });
  writeNpm(options.root, releases);
  const cargo = writeCargo(options.root, options.baseUrl, releases);
  const swift = writeSwift(options.root, scope, releases);
  writePub(options.root, releases);
  const maven = writeMaven(options.root, releases);
  writeFile(options.root, "_headers", HEADERS);
  const archiveBase = swiftEntries.length > 0 ? options.archiveBase : undefined;
  if (swiftEntries.length > 0 && archiveBase === undefined) {
    throw new Error("a scanned release ships a Swift lane; --archive-base is required");
  }
  const lines = buildRedirectLines({ archiveBase, swift, cargo, maven });
  guardRuleCounts(countRules(lines));
  writeFile(options.root, "_redirects", `${lines.join("\n")}\n`);
}
