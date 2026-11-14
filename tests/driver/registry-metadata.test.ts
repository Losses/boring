import { afterEach, expect, test } from "bun:test";
import {
  chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

/**
 * The pack action, given a Gradle maven-publish directory, must label every
 * file with the artifactId of its directory and collect the module metadata,
 * so one Kotlin Multiplatform version carries a root coordinate and eight
 * target coordinates. The registry tool then emits one maven-metadata.xml and
 * one redirect rule per artifactId, and an old single-artifactId directory
 * still produces the alpha07 registry shape.
 *
 * The Gradle publication itself is not produced here: pack does not call
 * Gradle. The test writes the publication directory Gradle would write
 * (maven/<groupPath>/<artifactId>/<version>/<artifactId>-<version>.<ext>).
 */
const ROOT = resolve(import.meta.dir, "../..");
const DRIVER = resolve(ROOT, "out/driver/driver.js");
const ASSET_BASE = "https://assets.example.test";

const dirs: string[] = [];
afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

interface RunResult { code: number; output: string }

interface MavenArtifactEntry { file: string; url: string; artifactId: string }

function run(command: string[], env: Record<string, string> = {}): RunResult {
  const result = Bun.spawnSync(command, {
    cwd: ROOT,
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  return { code: result.exitCode, output: result.stdout.toString() + result.stderr.toString() };
}

interface Fixture { dir: string; file: string }

function fixture(bundle: Record<string, unknown>): Fixture {
  const dir = mkdtempSync(join(tmpdir(), "boring-pack-registry-"));
  dirs.push(dir);
  const file = join(dir, "boring.json");
  writeFileSync(file, JSON.stringify({
    outRoot: "out",
    resultsDir: "results",
    baseline: "reference",
    sourceRoots: [],
    bundles: [bundle],
  }));
  return { dir, file };
}

/** A stub toolchain: pack only needs haxe and kotlinc to exist and exit 0. */
function fakeToolchain(dir: string): void {
  const bin = join(dir, "bin");
  mkdirSync(bin);
  for (const tool of ["haxe", "kotlinc"]) {
    const path = join(bin, tool);
    writeFileSync(path, "#!/bin/sh\nexit 0\n");
    chmodSync(path, 0o755);
  }
}

function writeFile(path: string, text: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}

function pack(current: Fixture, owner: string, repo: string): RunResult {
  return run([
    process.execPath, DRIVER, "pack", "reference", "--project", current.file,
    "--registry-out", "registry-out", "--owner", owner, "--repo", repo,
    "--asset-base", ASSET_BASE,
  ], { PATH: join(current.dir, "bin") + ":" + (process.env.PATH ?? "") });
}

let registryBuild: RunResult | null = null;
function generateRegistry(tree: string, output: string): RunResult {
  if (registryBuild === null) {
    registryBuild = run(["haxe", "packages/registry/compile.hxml"]);
  }
  if (registryBuild.code !== 0) throw new Error("registry compile failed: " + registryBuild.output);
  return run([
    "bun", "packages/registry/run.ts", "--tree", tree, "--output", output,
    "--base-url", "https://registry.example.test", "--swift-scope", "tiqian",
    "--archive-base", "https://archive.example.test",
  ]);
}

function filesUnder(root: string): string[] {
  return readdirSync(root, { recursive: true })
    .map(String)
    .filter((entry) => statSync(join(root, entry)).isFile())
    .sort();
}

const VERSION = "0.1.0-alpha08";
const ROOT_ID = "tiqian-engine";
const TARGETS = ["jvm", "android", "iosarm64", "iossimulatorarm64", "macosarm64", "linuxx64", "linuxarm64", "mingwx64"];
const IDS = [ROOT_ID].concat(TARGETS.map((target) => ROOT_ID + "-" + target));

test("pack labels every Gradle maven file with its artifactId and collects .module", async () => {
  const current = fixture({
    id: "reference",
    target: "kotlin",
    haxeArgs: ["-D", "package-artifact-stem=" + ROOT_ID],
    package: { name: ROOT_ID, version: VERSION, license: "MPL-2.0" },
  });
  fakeToolchain(current.dir);
  const group = join(current.dir, "out", "reference", "maven", "org", "tiqian");

  // The root coordinate is packaging=pom; every target publishes a pom beside
  // its Gradle module metadata, and the payload differs by target: jar for the
  // JVM, aar for Android, klib for Kotlin/Native.
  writeFile(join(group, ROOT_ID, VERSION, ROOT_ID + "-" + VERSION + ".pom"), "root pom");
  for (const id of IDS.slice(1)) {
    writeFile(join(group, id, VERSION, id + "-" + VERSION + ".pom"), id + " pom");
    writeFile(join(group, id, VERSION, id + "-" + VERSION + ".module"), id + " module");
  }
  writeFile(join(group, ROOT_ID + "-jvm", VERSION, ROOT_ID + "-jvm-" + VERSION + ".jar"), "jar");
  writeFile(join(group, ROOT_ID + "-android", VERSION, ROOT_ID + "-android-" + VERSION + ".aar"), "aar");
  writeFile(join(group, ROOT_ID + "-iosarm64", VERSION, ROOT_ID + "-iosarm64-" + VERSION + ".klib"), "klib");

  const packed = pack(current, "tiqian-cjk", "tiqian");
  expect(packed.code, packed.output).toBe(0);

  const metadataPath = join(current.dir, "registry-out", "tiqian-cjk", ROOT_ID, VERSION, "maven", "metadata.json");
  const metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
  expect(metadata.groupId).toBe("org.tiqian");
  const artifacts = metadata.artifacts as MavenArtifactEntry[];
  expect(artifacts.length).toBe(20);
  expect([...new Set(artifacts.map((entry) => entry.artifactId))].sort()).toEqual([...IDS].sort());
  for (const entry of artifacts) {
    expect(entry.artifactId.length, entry.file).toBeGreaterThan(0);
    expect(entry.url, entry.file).toBe(ASSET_BASE + "/" + entry.file);
  }
  const pick = (file: string) => artifacts.find((entry) => entry.file === file)!;
  expect(pick(ROOT_ID + "-jvm-" + VERSION + ".module").artifactId).toBe("tiqian-engine-jvm");
  expect(pick(ROOT_ID + "-iosarm64-" + VERSION + ".klib").artifactId).toBe("tiqian-engine-iosarm64");
  expect(pick(ROOT_ID + "-android-" + VERSION + ".aar").artifactId).toBe("tiqian-engine-android");

  const site = join(current.dir, "site");
  const generated = generateRegistry(join(current.dir, "registry-out"), site);
  expect(generated.code, generated.output).toBe(0);
  for (const id of IDS) {
    const xml = join(site, "maven", "org", "tiqian", id, "maven-metadata.xml");
    expect(existsSync(xml), id + " has no metadata document").toBe(true);
    const text = readFileSync(xml, "utf8");
    expect(text, id).toContain("<artifactId>" + id + "</artifactId>");
    expect(text, id).toContain("<version>" + VERSION + "</version>");
  }
  const redirects = readFileSync(join(site, "_redirects"), "utf8");
  for (const entry of artifacts) {
    const rule = "/maven/org/tiqian/" + entry.artifactId + "/:version/" + entry.file
      + "  https://github.com/tiqian-cjk/tiqian/releases/download/v:version/" + entry.file + "  302";
    expect(redirects, entry.file).toContain(rule);
  }
}, 300_000);

test("a single-artifactId Gradle directory keeps the alpha07 registry shape", async () => {
  const name = "tiqian-engine-f64";
  const version = "0.1.0-alpha07";
  const current = fixture({
    id: "reference",
    target: "kotlin",
    package: { name, version, license: "MPL-2.0" },
  });
  fakeToolchain(current.dir);
  const versionDir = join(current.dir, "out", "reference", "maven", name, name, version);
  writeFile(join(versionDir, name + "-" + version + ".jar"), "jar");
  writeFile(join(versionDir, name + "-" + version + ".pom"), "pom");

  const packed = pack(current, "tiqian-cjk", "tiqian");
  expect(packed.code, packed.output).toBe(0);
  const metadata = JSON.parse(readFileSync(
    join(current.dir, "registry-out", "tiqian-cjk", name, version, "maven", "metadata.json"), "utf8"));
  expect(metadata.groupId).toBe(name);
  const artifacts = metadata.artifacts as MavenArtifactEntry[];
  expect(artifacts.length).toBe(2);
  for (const entry of artifacts) expect(entry.artifactId, entry.file).toBe(name);

  const packedSite = join(current.dir, "site-packed");
  expect(generateRegistry(join(current.dir, "registry-out"), packedSite).code).toBe(0);

  // The same tree with the alpha07 metadata, whose artifact objects carry no
  // artifactId at all: the registry falls back to the metadata name.
  const reference = join(current.dir, "reference-tree");
  writeFile(join(reference, "tiqian-cjk", name, "README.md"), "# " + name + "\n");
  writeFile(join(reference, "tiqian-cjk", name, version, "maven", "metadata.json"), JSON.stringify({
    name,
    version,
    license: "MPL-2.0",
    repository: "tiqian-cjk/tiqian",
    tag: "v" + version,
    groupId: name,
    artifacts: [
      { file: name + "-" + version + ".jar", url: ASSET_BASE + "/" + name + "-" + version + ".jar" },
      { file: name + "-" + version + ".pom", url: ASSET_BASE + "/" + name + "-" + version + ".pom" },
    ],
  }));
  const referenceSite = join(current.dir, "site-reference");
  const referenceResult = generateRegistry(reference, referenceSite);
  expect(referenceResult.code, referenceResult.output).toBe(0);

  const packedFiles = filesUnder(packedSite);
  expect(packedFiles).toEqual(filesUnder(referenceSite));
  for (const path of packedFiles) {
    expect(readFileSync(join(packedSite, path)).equals(readFileSync(join(referenceSite, path))), path).toBe(true);
  }
  expect(packedFiles).toContain(join("maven", name, name, "maven-metadata.xml"));
}, 300_000);
