import { afterEach, expect, test } from "bun:test";
import {
  chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

/**
 * The pack action runs the bundle's publication command, then labels every file
 * of the staged Gradle maven-publish directory with the artifactId of its
 * directory and collects the module metadata, so one Kotlin Multiplatform
 * version carries a root coordinate and eight target coordinates. The staged
 * directory holds one package's publications, so no file name is filtered by
 * the package stem. The registry tool then emits
 * one maven-metadata.xml and one redirect rule per artifactId, and an old
 * single-artifactId directory still produces the alpha07 registry shape.
 *
 * The test's publication command stands in for Gradle: it writes the
 * publication directory
 * (maven/<groupPath>/<artifactId>/<version>/<artifactId>-<version>.<ext>)
 * into the {maven} directory the driver passes on the command line.
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

test("pack runs the publication command and labels every Gradle maven file", async () => {
  const current = fixture({
    id: "reference",
    target: "kotlin",
    haxeArgs: ["-D", "package-artifact-stem=" + ROOT_ID],
    package: { name: ROOT_ID, version: VERSION, license: "MPL-2.0" },
  });
  fakeToolchain(current.dir);
  const project = JSON.parse(readFileSync(current.file, "utf8"));
  project.bundles[0].mavenPublication = { command: process.execPath, args: [join(current.dir, "publish.ts"), "{maven}"] };
  writeFileSync(current.file, JSON.stringify(project));

  // The publication command stands in for Gradle. The root coordinate is
  // packaging=pom; every target publishes a pom beside its Gradle module
  // metadata, and the payload differs by target: jar for the JVM, aar for
  // Android, klib for Kotlin/Native.
  writeFile(join(current.dir, "publish.ts"), [
    'import { mkdirSync, writeFileSync } from "node:fs";',
    'import { dirname, join } from "node:path";',
    'const maven = process.argv[2];',
    'const group = join(maven, "org", "tiqian");',
    'const root = "tiqian-engine";',
    'const version = "0.1.0-alpha08";',
    'const targets = ["jvm", "android", "iosarm64", "iossimulatorarm64", "macosarm64", "linuxx64", "linuxarm64", "mingwx64"];',
    'function put(id, name, text) {',
    '  const path = join(group, id, version, name);',
    '  mkdirSync(dirname(path), { recursive: true });',
    '  writeFileSync(path, text);',
    '}',
    'put(root, root + "-" + version + ".pom", "root pom");',
    'for (const target of targets) {',
    '  const id = root + "-" + target;',
    '  put(id, id + "-" + version + ".pom", id + " pom");',
    '  put(id, id + "-" + version + ".module", id + " module");',
    '}',
    'put(root + "-jvm", root + "-jvm-" + version + ".jar", "jar");',
    'put(root + "-android", root + "-android-" + version + ".aar", "aar");',
    'put(root + "-iosarm64", root + "-iosarm64-" + version + ".klib", "klib");',
    'writeFileSync(join(maven, "publication-ran.txt"), maven);',
  ].join("\n"));

  const packed = pack(current, "tiqian-cjk", "tiqian");
  expect(packed.code, packed.output).toBe(0);
  const mavenDir = join(current.dir, "out", "reference", "maven");
  expect(readFileSync(join(mavenDir, "publication-ran.txt"), "utf8")).toBe(mavenDir);

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
  const mavenRules = redirects.split("\n").filter((line) => line.startsWith("/maven/"));
  expect(mavenRules).toEqual(["/maven/org/tiqian/:artifact/:version/:file  https://github.com/tiqian-cjk/tiqian/releases/download/v:version/:file  302"]);
}, 300_000);

test("pack collects every publication directory in the staged maven tree", async () => {
  const current = fixture({
    id: "reference",
    target: "kotlin",
    haxeArgs: ["-D", "package-artifact-stem=" + ROOT_ID],
    package: { name: ROOT_ID, version: VERSION, license: "MPL-2.0" },
  });
  fakeToolchain(current.dir);
  const project = JSON.parse(readFileSync(current.file, "utf8"));
  project.bundles[0].mavenPublication = { command: process.execPath, args: [join(current.dir, "publish.ts"), "{maven}"] };
  writeFileSync(current.file, JSON.stringify(project));
  writeFile(join(current.dir, "publish.ts"), [
    'import { mkdirSync, writeFileSync } from "node:fs";',
    'import { dirname, join } from "node:path";',
    'const maven = process.argv[2];',
    'function put(id, name, text) {',
    '  const path = join(maven, "org", "tiqian", id, version, name);',
    '  mkdirSync(dirname(path), { recursive: true });',
    '  writeFileSync(path, text);',
    '}',
    'const version = "0.1.0-alpha08";',
    'put("tiqian-engine", "tiqian-engine-" + version + ".pom", "root pom");',
    'put("tiqian-engine-android", "tiqian-engine-android-" + version + ".pom", "android pom");',
    'put("tiqian-engine-android", "tiqian-engine-android-" + version + ".module", "android module");',
    'put("engine-iosarm64", "engine-iosarm64-" + version + ".pom", "apple pom");',
    'put("engine-iosarm64", "engine-iosarm64-" + version + ".module", "apple module");',
  ].join("\n"));

  const packed = pack(current, "tiqian-cjk", "tiqian");
  expect(packed.code, packed.output).toBe(0);
  const metadata = JSON.parse(readFileSync(
    join(current.dir, "registry-out", "tiqian-cjk", ROOT_ID, VERSION, "maven", "metadata.json"), "utf8"));
  const artifacts = metadata.artifacts as MavenArtifactEntry[];
  expect(artifacts.length).toBe(5);
  expect([...new Set(artifacts.map((entry) => entry.artifactId))].sort())
    .toEqual(["engine-iosarm64", "tiqian-engine", "tiqian-engine-android"]);
});

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


/**
 * A scoped npm package name (feature spec 59): the metadata name keeps the
 * scope, the tree directory encodes the scope separator so it stays one
 * path segment, and the artifact file repeats the compiler's own stem
 * rewrite. The generated npm document carries the scoped name the client
 * asks for.
 */
test("a scoped npm name keeps the scope in metadata and encodes the tree directory", async () => {
  const current = fixture({
    id: "reference",
    target: "ts",
    package: { name: "tiqian-protocol", version: VERSION, license: "MPL-2.0", npmName: "@tiqian/protocol" },
  });
  const bin = join(current.dir, "bin");
  const archiveName = "@tiqian-protocol-" + VERSION + ".tgz";
  // The compiler writes the npm tarball beside the output tree; this stub
  // writes the file the compiler would, from the output directory the
  // driver passes.
  writeFile(join(bin, "haxe"), [
    "#!/usr/bin/env bun",
    'import { mkdirSync, writeFileSync } from "node:fs";',
    'import { dirname, join } from "node:path";',
    "const args = process.argv.slice(2);",
    'const output = args.find((arg) => arg.startsWith("ts-output="))?.slice("ts-output=".length);',
    "if (output) {",
    "  const parent = dirname(output);",
    "  mkdirSync(parent, { recursive: true });",
    '  writeFileSync(join(parent, ' + JSON.stringify(archiveName) + '), Buffer.from("fake npm archive"));',
    "}",
    "",
  ].join("\n"));
  writeFile(join(bin, "tsc"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "haxe"), 0o755);
  chmodSync(join(bin, "tsc"), 0o755);

  const packed = pack(current, "tiqian-cjk", "tiqian");
  expect(packed.code, packed.output).toBe(0);
  const metadata = JSON.parse(readFileSync(join(
    current.dir, "registry-out", "tiqian-cjk", "@tiqian%2fprotocol", VERSION, "npm", "metadata.json"), "utf8"));
  expect(metadata.name).toBe("@tiqian/protocol");
  expect(metadata.url).toBe(ASSET_BASE + "/" + archiveName);

  const site = join(current.dir, "site");
  const generated = generateRegistry(join(current.dir, "registry-out"), site);
  expect(generated.code, generated.output).toBe(0);
  const document = JSON.parse(readFileSync(join(site, "npm", "@tiqian", "protocol"), "utf8"));
  expect(document.name).toBe("@tiqian/protocol");
  expect(document["dist-tags"].latest).toBe(VERSION);
}, 300_000);
