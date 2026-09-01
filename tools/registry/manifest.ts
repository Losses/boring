/**
 * The release manifest reader (spec 26 ruling 2). The release pipeline
 * writes the manifest into the release body as the first fenced code
 * block tagged `boring`, holding one JSON object. A release participates
 * in the registry if and only if its body carries that block, and the
 * manifest is the authority for identity, digests, and document fields:
 * the generator never opens an artifact.
 */

import { requireSemver } from "./semver.ts";

/** The npm lane: tarball asset name plus the base64 sha512 of its bytes. */
export type NpmLane = { artifact: string; sha512: string };

/** The cargo lane: crate asset name plus the hex sha256 of its bytes. */
export type CargoLane = { artifact: string; sha256: string };

/**
 * The pubspec the spec 24 emitter writes: name, version, license, and
 * environment.sdk, and no other key.
 */
/** The environment section of a pubspec: only the sdk constraint. */
export type PubspecEnvironment = { sdk: string };

export type Pubspec = {
  name: string;
  version: string;
  license?: string;
  environment?: PubspecEnvironment;
};

/** The Pub lane: archive asset name, hex sha256, and the pubspec. */
export type PubLane = { artifact: string; sha256: string; pubspec: Pubspec };

/**
 * The Swift lane: the object key under the archive base, the hex sha256
 * of the zip bytes, and the Package.swift source text.
 */
export type SwiftLane = { archive: string; sha256: string; packageSwift: string };

/** The Maven lane: the groupId and the asset names of one release. */
export type MavenLane = { groupId: string; artifacts: string[] };

/** One release manifest: the spec 24 identity plus the shipped lanes. */
export type Manifest = {
  name: string;
  version: string;
  license?: string;
  npm?: NpmLane;
  cargo?: CargoLane;
  pub?: PubLane;
  swift?: SwiftLane;
  maven?: MavenLane;
};

const PUBSPEC_KEYS = new Set(["name", "version", "license", "environment"]);

class ManifestError extends Error {}

function fail(repo: string, tag: string, reason: string): never {
  throw new ManifestError(`${repo} release ${tag}: ${reason}`);
}

function readString(value: unknown, repo: string, tag: string, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    fail(repo, tag, `${label} must be a non-empty string`);
  }
  return value;
}

function readPubspec(value: unknown, repo: string, tag: string): Pubspec {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(repo, tag, "pubspec must be an object");
  }
  const raw = value as Record<string, unknown>;
  const pubspec: Pubspec = {
    name: "",
    version: "",
  };
  for (const key of Object.keys(raw)) {
    if (!PUBSPEC_KEYS.has(key)) {
      fail(repo, tag, `pubspec key ${key} is outside the spec 24 grammar`);
    }
  }
  pubspec.name = readString(raw.name, repo, tag, "pubspec name");
  pubspec.version = readString(raw.version, repo, tag, "pubspec version");
  if (raw.license !== undefined) {
    pubspec.license = readString(raw.license, repo, tag, "pubspec license");
  }
  if (raw.environment !== undefined) {
    if (!raw.environment || typeof raw.environment !== "object" || Array.isArray(raw.environment)) {
      fail(repo, tag, "pubspec environment must be an object");
    }
    const env = raw.environment as Record<string, unknown>;
    for (const key of Object.keys(env)) {
      if (key !== "sdk") {
        fail(repo, tag, `pubspec key ${key} is outside the spec 24 grammar`);
      }
    }
    pubspec.environment = { sdk: readString(env.sdk, repo, tag, "pubspec environment sdk") };
  }
  return pubspec;
}

/** Reads one lane object through the lane-specific field reader. */
type LaneReader<T> = (raw: Record<string, unknown>) => T;

function readLane<T>(
  value: unknown,
  repo: string,
  tag: string,
  lane: string,
  read: LaneReader<T>,
): T {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(repo, tag, `lane ${lane} must be an object`);
  }
  return read(value as Record<string, unknown>);
}

/**
 * Reads the manifest out of one release body. Returns undefined when the
 * body carries no `boring` block; throws, naming the repository and tag,
 * when a present block does not parse or does not conform to the field
 * table.
 */
export function parseManifest(body: string, repo: string, tag: string): Manifest | undefined {
  const block = /```boring\s*\n([\s\S]*?)\n```/.exec(body);
  if (!block) {
    return undefined;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(block[1] ?? "");
  } catch {
    fail(repo, tag, "manifest block is not valid JSON");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    fail(repo, tag, "manifest block is not a JSON object");
  }
  const raw = parsed as Record<string, unknown>;
  const manifest: Manifest = {
    name: "",
    version: "",
  };
  manifest.name = readString(raw.name, repo, tag, "name");
  manifest.version = readString(raw.version, repo, tag, "version");
  requireSemver(manifest.version, `${repo} release ${tag}`);
  if (raw.license !== undefined) {
    manifest.license = readString(raw.license, repo, tag, "license");
  }
  if (raw.npm !== undefined) {
    manifest.npm = readLane(raw.npm, repo, tag, "npm", (lane) => ({
      artifact: readString(lane.artifact, repo, tag, "npm artifact"),
      sha512: readString(lane.sha512, repo, tag, "npm sha512"),
    }));
  }
  if (raw.cargo !== undefined) {
    manifest.cargo = readLane(raw.cargo, repo, tag, "cargo", (lane) => ({
      artifact: readString(lane.artifact, repo, tag, "cargo artifact"),
      sha256: readString(lane.sha256, repo, tag, "cargo sha256"),
    }));
  }
  if (raw.pub !== undefined) {
    manifest.pub = readLane(raw.pub, repo, tag, "pub", (lane) => ({
      artifact: readString(lane.artifact, repo, tag, "pub artifact"),
      sha256: readString(lane.sha256, repo, tag, "pub sha256"),
      pubspec: readPubspec(lane.pubspec, repo, tag),
    }));
  }
  if (raw.swift !== undefined) {
    manifest.swift = readLane(raw.swift, repo, tag, "swift", (lane) => ({
      archive: readString(lane.archive, repo, tag, "swift archive"),
      sha256: readString(lane.sha256, repo, tag, "swift sha256"),
      packageSwift: readString(lane.packageSwift, repo, tag, "swift packageSwift"),
    }));
  }
  if (raw.maven !== undefined) {
    manifest.maven = readLane(raw.maven, repo, tag, "maven", (lane) => {
      const groupId = readString(lane.groupId, repo, tag, "maven groupId");
      if (!Array.isArray(lane.artifacts) || lane.artifacts.length === 0) {
        fail(repo, tag, "maven artifacts must be a non-empty array");
      }
      const artifacts = lane.artifacts.map((file) => readString(file, repo, tag, "maven artifact"));
      return { groupId, artifacts };
    });
  }
  return manifest;
}
