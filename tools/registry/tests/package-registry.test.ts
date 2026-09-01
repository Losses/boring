import { describe, expect, test } from "bun:test";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const ROOT = path.resolve(import.meta.dir, "../../..");
const BASE = "https://registry.example.test/root";
const SCOPE = "acme";
let fixtureBase = "https://assets.example.test";

interface CommandResult {
  code: number;
  output: string;
}

interface FixtureOptions {
  malformed?: string;
  stray?: boolean;
  disagreement?: boolean;
  uppercaseCargo?: boolean;
  omitReadme?: boolean;
  omitVersion?: boolean;
  missingDigest?: boolean;
  digestConflict?: boolean;
}

type Metadata = Record<string, unknown>;

function sha256(text: string): string {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function sha512(text: string): string {
  return crypto.createHash("sha512").update(text).digest("base64");
}

function metadata(platform: string, name: string, version: string, owner: string, repo: string, options: FixtureOptions = {}): Metadata {
  const suffix = `${owner}/${repo}/${version}`;
  const packageName = options.uppercaseCargo === true ? "Acme-Core" : name;
  const result: Metadata = { name: packageName, version, license: "MIT" };
  if(platform === "npm") {
    result.url = `${fixtureBase}/${suffix}/package.tgz`;
    result.sha512 = options.missingDigest === true ? "" : sha512(`npm-${suffix}`);
  } else if(platform === "cargo") {
    result.url = `${fixtureBase}/${suffix}/package.crate`;
    result.sha256 = sha256(`cargo-${suffix}`);
  } else if(platform === "pub") {
    result.url = `${fixtureBase}/${suffix}/package.tar.gz`;
    result.sha256 = sha256(`pub-${suffix}`);
    result.pubspec = { name: packageName, version, license: "MIT", environment: { sdk: ">=3.0.0 <4.0.0" } };
  } else if(platform === "swift") {
    result.archive = `swift/${SCOPE}/${packageName}/${version}.zip`;
    result.sha256 = sha256(`swift-${suffix}`);
    result.packageSwift = `// Package ${packageName} ${version}\n`;
  } else {
    result.groupId = "dev.acme";
    result.artifacts = [
      { file: `acme-core-${version}.jar`, url: `${fixtureBase}/${suffix}/core.jar` },
      { file: `acme-core-${version}.pom`, url: `${fixtureBase}/${suffix}/core.pom` },
      { file: `acme-core-${version}.jar.sha1`, url: `${fixtureBase}/${suffix}/core.jar.sha1` },
      { file: `acme-core-${version}.pom.sha1`, url: `${fixtureBase}/${suffix}/core.pom.sha1` },
    ];
  }
  return result;
}

function writeJson(file: string, value: unknown): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function createFixture(label: string, options: FixtureOptions = {}): string {
  const tree = fs.mkdtempSync(path.join(os.tmpdir(), `boring-registry-${label}-`));
  const repo = path.join(tree, "acme", "core");
  if(options.omitReadme !== true) {
    fs.mkdirSync(repo, { recursive: true });
    fs.writeFileSync(path.join(repo, "README.md"), "# Acme Core\n\nCommitted README.\n");
  }
  if(options.omitVersion !== true) {
    for(const version of ["1.0.0", "1.1.0"]) {
      for(const platform of ["npm", "cargo", "pub", "swift", "maven"]) {
        const value = metadata(platform, "acme-core", version, "acme", "core", options);
        if(options.disagreement === true && platform !== "cargo") value.name = "different-name";
        const file = path.join(repo, version, platform, "metadata.json");
        if(options.malformed !== undefined && platform === options.malformed) {
          fs.mkdirSync(path.dirname(file), { recursive: true });
          fs.writeFileSync(file, "{ malformed\n");
        } else {
          writeJson(file, value);
        }
      }
    }
  }
  const second = path.join(tree, "acme", "tools");
  fs.mkdirSync(second, { recursive: true });
  fs.writeFileSync(path.join(second, "README.md"), "# Tools\n");
  writeJson(path.join(second, "2.0.0", "npm", "metadata.json"), {
    name: "@acme/tools", version: "2.0.0", license: "Apache-2.0",
    url: `${fixtureBase}/tools.tgz`, sha512: sha512("tools"),
  });
  if(options.digestConflict === true) {
    const conflicting = path.join(tree, "acme", "other");
    fs.mkdirSync(path.join(conflicting, "1.0.0", "npm"), { recursive: true });
    fs.writeFileSync(path.join(conflicting, "README.md"), "# Other\n");
    writeJson(path.join(conflicting, "1.0.0", "npm", "metadata.json"), {
      name: "acme-core", version: "1.0.0", license: "MIT",
      url: "https://assets.example.test/conflict.tgz", sha512: "different-digest",
    });
  }
  if(options.stray === true) fs.writeFileSync(path.join(repo, "notes.txt"), "not metadata");
  return tree;
}

let compilation: Promise<CommandResult> | undefined;
function compileRegistry(): Promise<CommandResult> {
  compilation ??= run(["haxe", "tools/registry/compile.hxml"]);
  return compilation;
}

async function run(args: string[], cwd = ROOT): Promise<CommandResult> {
  const process = Bun.spawn(args, { cwd, stdout: "pipe", stderr: "pipe" });
  const [code, stdout, stderr] = await Promise.all([
    process.exited,
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
  ]);
  return { code, output: `${stdout}${stderr}` };
}

async function generate(tree: string, output: string, extras: string[] = [], archiveBase = "https://archive.example.test"): Promise<CommandResult> {
  await compileRegistry();
  const args = ["bun", "tools/registry/run.ts", "--tree", tree, "--output", output, "--base-url", BASE, "--swift-scope", SCOPE, "--archive-base", archiveBase, ...extras];
  return run(args);
}

function files(root: string): string[] {
  return fs.readdirSync(root, { recursive: true }).map(String).filter((entry) => fs.statSync(path.join(root, entry)).isFile()).sort();
}

describe("committed package registry", () => {
  test("writes all five namespaces and stable bytes", async () => {
    const first = fs.mkdtempSync(path.join(os.tmpdir(), "boring-site-a-"));
    const second = fs.mkdtempSync(path.join(os.tmpdir(), "boring-site-b-"));
    fs.rmSync(first, { recursive: true });
    fs.rmSync(second, { recursive: true });
    let tree = "";
    try {
      const server = Bun.serve({ port: 0, fetch: () => new Response("fixture asset") });
      fixtureBase = `http://127.0.0.1:${server.port}`;
      try {
      tree = createFixture("complete");
      const result = await generate(tree, first, [], fixtureBase);
      expect(result.code).toBe(0);
      const npm = JSON.parse(fs.readFileSync(path.join(first, "npm/acme-core"), "utf8")) as Record<string, unknown>;
      expect(npm["dist-tags"]).toEqual({ latest: "1.1.0" });
      expect(npm.readme).toBe("# Acme Core\n\nCommitted README.\n");
      const versions = npm.versions as Record<string, Record<string, unknown>>;
      expect(versions["1.0.0"]?.dist).toEqual({ tarball: `${fixtureBase}/acme/core/1.0.0/package.tgz`, integrity: `sha512-${sha512("npm-acme/core/1.0.0")}` });
      expect(fs.existsSync(path.join(first, "npm/@acme%2ftools"))).toBe(true);
      expect(JSON.parse(fs.readFileSync(path.join(first, "cargo/index/config.json"), "utf8"))).toEqual({ dl: `${BASE}/cargo/dl/{crate}-{version}.crate` });
      expect(fs.readFileSync(path.join(first, "cargo/index/ac/me/acme-core"), "utf8")).toContain('"cksum":"');
      expect(JSON.parse(fs.readFileSync(path.join(first, "swift/acme/acme-core.json"), "utf8")).releases).toEqual({ "1.0.0": {}, "1.1.0": {} });
      expect(fs.readFileSync(path.join(first, "swift/acme/acme-core/1.1.0/Package.swift"), "utf8")).toBe("// Package acme-core 1.1.0\n");
      expect(JSON.parse(fs.readFileSync(path.join(first, "swift/identifiers"), "utf8"))).toEqual([]);
      const pub = JSON.parse(fs.readFileSync(path.join(first, "pub/api/packages/acme-core"), "utf8")) as Record<string, unknown>;
      expect(pub.latest).toBe("1.1.0");
      expect((pub.versions as Array<Record<string, unknown>>)[0]?.pubspec).toHaveProperty("environment");
      const pom = path.join(first, "maven/dev/acme/acme-core/maven-metadata.xml");
      expect(fs.readFileSync(pom, "utf8")).toContain("<version>1.1.0</version>");
      expect(fs.readFileSync(`${pom}.sha1`, "utf8")).toBe(`${crypto.createHash("sha1").update(fs.readFileSync(pom)).digest("hex")}\n`);
      expect(fs.readFileSync(path.join(first, "_headers"), "utf8")).toContain("Content-Version: 1");
      expect(fs.readFileSync(path.join(first, "_redirects"), "utf8")).toContain("/swift/:scope/:name/*.zip");
      const again = await generate(tree, second, [], fixtureBase);
      expect(again.code).toBe(0);
      expect(files(first)).toEqual(files(second));
      for(const file of files(first)) expect(fs.readFileSync(path.join(first, file))).toEqual(fs.readFileSync(path.join(second, file)));
      } finally { server.stop(); fixtureBase = "https://assets.example.test"; }
    } finally { fs.rmSync(tree, { recursive: true, force: true }); fs.rmSync(first, { recursive: true, force: true }); fs.rmSync(second, { recursive: true, force: true }); }
  }, 120000);

  type NegativeCase = [string, FixtureOptions, string[], string];
  const negatives: NegativeCase[] = [
    ["stray files", { stray: true }, [], "notes.txt"],
    ["malformed metadata", { malformed: "npm" }, [], "metadata"],
    ["missing README", { omitReadme: true }, [], "README"],
    ["missing version", { omitVersion: true }, [], "version"],
    ["platform disagreement", { disagreement: true }, [], "disagree"],
    ["uppercase Cargo name", { uppercaseCargo: true }, [], "lowercase"],
    ["missing Swift flags", {}, ["--swift-scope", ""], "swift"],
    ["missing Swift archive base", {}, ["--archive-base", ""], "archive-base"],
    ["invalid URL scheme", {}, ["--base-url", "file:///site"], "http"],
    ["digest conflict", { digestConflict: true }, [], "digest"],
  ];
  for(const [label, options, extras, message] of negatives) {
    test(`rejects ${label}`, async () => {
      const tree = createFixture(`negative-${label.replaceAll(" ", "-")}`, options);
      const output = path.join(tree, "out");
      try { const result = await generate(tree, output, extras); expect(result.code).not.toBe(0); expect(result.output.toLowerCase()).toContain(message.toLowerCase()); }
      finally { fs.rmSync(tree, { recursive: true, force: true }); }
    });
  }

  test("rejects missing required flags", async () => {
    await compileRegistry();
    const result = await run(["bun", "tools/registry/run.ts", "--tree", "/tmp/no-such-tree"]);
    expect(result.code).not.toBe(0);
    expect(result.output).toContain("--output");
  });
});
