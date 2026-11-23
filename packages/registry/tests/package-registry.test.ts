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
  compilation ??= run(["haxe", "packages/registry/compile.hxml"]);
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
  const args = ["bun", "packages/registry/run.ts", "--tree", tree, "--output", output, "--base-url", BASE, "--swift-scope", SCOPE, "--archive-base", archiveBase, ...extras];
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
      // npm sends @acme%2ftools and the host decodes %2f before the file
      // lookup, so the packument file sits at the decoded path.
      expect(fs.existsSync(path.join(first, "npm/@acme/tools"))).toBe(true);
      expect(fs.existsSync(path.join(first, "npm/@acme%2ftools"))).toBe(false);
      expect(versions["1.0.0"]).not.toHaveProperty("dependencies");
      expect(JSON.parse(fs.readFileSync(path.join(first, "cargo/index/config.json"), "utf8"))).toEqual({ dl: `${BASE}/cargo/dl/{crate}-{version}.crate` });
      expect(fs.readFileSync(path.join(first, "cargo/index/ac/me/acme-core"), "utf8")).toContain('"cksum":"');
      expect(JSON.parse(fs.readFileSync(path.join(first, "swift/acme/acme-core.json"), "utf8")).releases).toEqual({ "1.0.0": {}, "1.1.0": {} });
      expect(fs.readFileSync(path.join(first, "swift/acme/acme-core/1.1.0/Package.swift"), "utf8")).toBe("// Package acme-core 1.1.0\n");
      expect(JSON.parse(fs.readFileSync(path.join(first, "swift/identifiers"), "utf8"))).toEqual([]);
      const pub = JSON.parse(fs.readFileSync(path.join(first, "pub/api/packages/acme-core"), "utf8")) as Record<string, unknown>;
      // The hosted pub API puts the latest version entry here; the version
      // string lives in its `version` field (registry/Core.hx writes it).
      expect((pub.latest as { version?: string }).version).toBe("1.1.0");
      expect((pub.latest as { archive_sha256?: string }).archive_sha256).toBeDefined();
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

  test("cargo index copies the metadata feature map and defaults to an empty one", async () => {
    const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-features-"));
    const output = path.join(tree, "out");
    try {
      const withFeatures = path.join(tree, "acme", "withfeat");
      fs.mkdirSync(path.join(withFeatures, "1.0.0", "cargo"), { recursive: true });
      fs.writeFileSync(path.join(withFeatures, "README.md"), "# With Features\n");
      writeJson(path.join(withFeatures, "1.0.0", "cargo", "metadata.json"), {
        name: "withfeat", version: "1.0.0", license: "MIT",
        url: `${fixtureBase}/withfeat.crate`, sha256: sha256("withfeat"),
        features: { f32: [] },
      });
      const withoutFeatures = path.join(tree, "acme", "nofeat");
      fs.mkdirSync(path.join(withoutFeatures, "1.0.0", "cargo"), { recursive: true });
      fs.writeFileSync(path.join(withoutFeatures, "README.md"), "# No Features\n");
      writeJson(path.join(withoutFeatures, "1.0.0", "cargo", "metadata.json"), {
        name: "nofeat", version: "1.0.0", license: "MIT",
        url: `${fixtureBase}/nofeat.crate`, sha256: sha256("nofeat"),
      });
      const result = await generate(tree, output);
      expect(result.code).toBe(0);
      const withLine = JSON.parse(fs.readFileSync(path.join(output, "cargo/index/wi/th/withfeat"), "utf8").trim()) as Record<string, unknown>;
      expect(withLine.features).toEqual({ f32: [] });
      const withoutLine = JSON.parse(fs.readFileSync(path.join(output, "cargo/index/no/fe/nofeat"), "utf8").trim()) as Record<string, unknown>;
      expect(withoutLine.features).toEqual({});
    } finally { fs.rmSync(tree, { recursive: true, force: true }); }
  }, 120000);

  test("rejects a cargo feature map that is not an object", async () => {
    const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-features-invalid-"));
    const output = path.join(tree, "out");
    try {
      const repo = path.join(tree, "acme", "badfeat");
      fs.mkdirSync(path.join(repo, "1.0.0", "cargo"), { recursive: true });
      fs.writeFileSync(path.join(repo, "README.md"), "# Bad Features\n");
      writeJson(path.join(repo, "1.0.0", "cargo", "metadata.json"), {
        name: "badfeat", version: "1.0.0", license: "MIT",
        url: `${fixtureBase}/badfeat.crate`, sha256: sha256("badfeat"),
        features: [],
      });
      const result = await generate(tree, output);
      expect(result.code).not.toBe(0);
      expect(result.output.toLowerCase()).toContain("invalid features");
    } finally { fs.rmSync(tree, { recursive: true, force: true }); }
  }, 120000);

  test("npm version entries copy the metadata manifest fields in a fixed order", async () => {
    const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-manifest-"));
    const output = path.join(tree, "out");
    try {
      const repo = path.join(tree, "acme", "client");
      fs.mkdirSync(path.join(repo, "1.0.0", "npm"), { recursive: true });
      fs.writeFileSync(path.join(repo, "README.md"), "# Client\n");
      writeJson(path.join(repo, "1.0.0", "npm", "metadata.json"), {
        name: "@acme/client", version: "1.0.0", license: "MIT",
        url: `${fixtureBase}/client.tgz`, sha512: sha512("client"),
        manifest: {
          cpu: ["arm64"],
          optionalDependencies: { "@acme/client-darwin-arm64": "1.0.0" },
          dependencies: { "@acme/tools": "2.0.0", "left-pad": "^1.3.0" },
          peerDependencies: { react: "^18.0.0 || ^19.0.0" },
        },
      });
      const result = await generate(tree, output);
      expect(result.code).toBe(0);
      const packument = JSON.parse(fs.readFileSync(path.join(output, "npm/@acme/client"), "utf8")) as Record<string, unknown>;
      const entry = (packument.versions as Record<string, Record<string, unknown>>)["1.0.0"] ?? {};
      expect(entry.dependencies).toEqual({ "@acme/tools": "2.0.0", "left-pad": "^1.3.0" });
      expect(entry.optionalDependencies).toEqual({ "@acme/client-darwin-arm64": "1.0.0" });
      expect(entry.peerDependencies).toEqual({ react: "^18.0.0 || ^19.0.0" });
      expect(entry.cpu).toEqual(["arm64"]);
      expect(Object.keys(entry)).toEqual(["name", "version", "license", "dependencies", "optionalDependencies", "peerDependencies", "cpu", "dist"]);
    } finally { fs.rmSync(tree, { recursive: true, force: true }); }
  }, 120000);

  type ManifestCase = [string, unknown, string];
  const manifestNegatives: ManifestCase[] = [
    ["a manifest that is not an object", ["dependencies"], "invalid manifest"],
    ["a manifest key outside the resolution fields", { scripts: { postinstall: "node x.js" } }, "unknown manifest key scripts"],
    ["dependencies that are not a map", { dependencies: "left-pad" }, "invalid manifest dependencies"],
    ["a dependency range that is not a string", { peerDependencies: { react: 18 } }, "invalid manifest peerDependencies"],
    ["peerDependenciesMeta entries that are not objects", { peerDependenciesMeta: { react: true } }, "invalid manifest peerDependenciesMeta"],
    ["cpu that is not a string list", { cpu: "arm64" }, "invalid manifest cpu"],
    ["os entries that are not strings", { os: ["linux", 1] }, "invalid manifest os"],
    ["a bin that is neither a path nor a path map", { bin: ["cli.js"] }, "invalid manifest bin"],
  ];
  for(const [label, manifest, expected] of manifestNegatives) {
    test(`rejects ${label}`, async () => {
      const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-manifest-invalid-"));
      const output = path.join(tree, "out");
      try {
        const repo = path.join(tree, "acme", "client");
        fs.mkdirSync(path.join(repo, "1.0.0", "npm"), { recursive: true });
        fs.writeFileSync(path.join(repo, "README.md"), "# Client\n");
        writeJson(path.join(repo, "1.0.0", "npm", "metadata.json"), {
          name: "client", version: "1.0.0", license: "MIT",
          url: `${fixtureBase}/client.tgz`, sha512: sha512("client"), manifest,
        });
        const result = await generate(tree, output);
        expect(result.code).not.toBe(0);
        expect(result.output).toContain(expected);
      } finally { fs.rmSync(tree, { recursive: true, force: true }); }
    }, 120000);
  }

  for(const name of ["../../escaped", "foo/bar", "@acme/../x", "Client", "@acme/tools/extra"]) {
    test(`rejects the npm name ${name}`, async () => {
      const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-npm-name-"));
      const output = path.join(tree, "out", "site");
      try {
        const repo = path.join(tree, "acme", "client");
        fs.mkdirSync(path.join(repo, "1.0.0", "npm"), { recursive: true });
        fs.writeFileSync(path.join(repo, "README.md"), "# Client\n");
        writeJson(path.join(repo, "1.0.0", "npm", "metadata.json"), {
          name, version: "1.0.0", license: "MIT",
          url: `${fixtureBase}/client.tgz`, sha512: sha512("client"),
        });
        const result = await generate(tree, output);
        expect(result.code).not.toBe(0);
        expect(result.output).toContain(`invalid npm name ${name}`);
        expect(fs.existsSync(path.join(tree, "out", "escaped"))).toBe(false);
      } finally { fs.rmSync(tree, { recursive: true, force: true }); }
    }, 120000);
  }

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
    const result = await run(["bun", "packages/registry/run.ts", "--tree", "/tmp/no-such-tree"]);
    expect(result.code).not.toBe(0);
    expect(result.output).toContain("--output");
  });

  test("one maven package directory carries a root coordinate and eight targets", async () => {
    const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-kmp-"));
    const output = path.join(tree, "out");
    const version = "0.1.0-alpha08";
    const targets = ["jvm", "android", "iosarm64", "iossimulatorarm64", "macosarm64", "linuxx64", "linuxarm64", "mingwx64"];
    const ids = ["tiqian-engine", ...targets.map((target) => "tiqian-engine-" + target)];
    try {
      const repo = path.join(tree, "tiqian-cjk", "tiqian-engine");
      fs.mkdirSync(path.join(repo, version, "maven"), { recursive: true });
      fs.writeFileSync(path.join(repo, "README.md"), "# tiqian-engine\n");
      const artifacts: { file: string; url: string; artifactId: string }[] = [];
      for(const id of ids) {
        for(const extension of [".pom", ".module"]) {
          // The root coordinate is packaging=pom; the eight targets publish a
          // module metadata file beside their pom.
          if(id === "tiqian-engine" && extension === ".module") continue;
          const file = id + "-" + version + extension;
          artifacts.push({ file, url: "https://assets.example.test/" + file, artifactId: id });
        }
      }
      writeJson(path.join(repo, version, "maven", "metadata.json"), {
        name: "tiqian-engine", version, license: "MPL-2.0", repository: "tiqian-cjk/tiqian",
        tag: "v" + version, groupId: "org.tiqian", artifacts,
      });
      const result = await generate(tree, output);
      expect(result.code).toBe(0);
      for(const id of ids) {
        const file = path.join(output, "maven", "org", "tiqian", id, "maven-metadata.xml");
        expect(fs.existsSync(file)).toBe(true);
        const xml = fs.readFileSync(file, "utf8");
        expect(xml).toContain("<groupId>org.tiqian</groupId>");
        expect(xml).toContain("<artifactId>" + id + "</artifactId>");
        expect(xml).toContain("<version>" + version + "</version>");
        expect(fs.readFileSync(file + ".sha1", "utf8")).toBe(crypto.createHash("sha1").update(xml).digest("hex") + "\n");
      }
      const redirects = fs.readFileSync(path.join(output, "_redirects"), "utf8");
      const mavenRules = redirects.split("\n").filter((line) => line.startsWith("/maven/"));
      expect(mavenRules).toEqual(["/maven/org/tiqian/:artifact/:version/:file  https://github.com/tiqian-cjk/tiqian/releases/download/v:version/:file  302"]);
    } finally { fs.rmSync(tree, { recursive: true, force: true }); }
  }, 120000);

  test("maven redirects stay fixed as versions grow and narrow only where routing needs it", async () => {
    const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-maven-rules-"));
    const output = path.join(tree, "out");
    try {
      const write = (name: string, repository: string, groupId: string, ids: string[], version: string) => {
        const repo = path.join(tree, "acme", name);
        fs.mkdirSync(path.join(repo, version, "maven"), { recursive: true });
        fs.writeFileSync(path.join(repo, "README.md"), "# " + name + "\n");
        const artifacts = ids.flatMap((id) => [".pom", ".jar", ".module", "-sources.jar"].map((extension) => {
          const file = id + "-" + version + extension;
          return { file, url: "https://assets.example.test/" + file, artifactId: id };
        }));
        writeJson(path.join(repo, version, "maven", "metadata.json"), {
          name, version, repository, tag: "v" + version, groupId, artifacts,
        });
      };
      // dev.acme spans repositories: 30 versions of 12 artifacts from
      // acme/core (1440 files), two artifacts from acme/ui, and one whose
      // repository changed between versions.
      const coreIds = Array.from({ length: 12 }, (_, i) => "core-" + i);
      for(let minor = 0; minor < 30; minor++) write("core", "acme/core", "dev.acme", coreIds, "1." + minor + ".0");
      write("ui", "acme/ui", "dev.acme", ["ui", "ui-android"], "2.0.0");
      write("moved", "acme/old", "dev.acme", ["moved"], "1.0.0");
      write("moved", "acme/new", "dev.acme", ["moved"], "2.0.0");
      // dev.solo has one repository but dev.solo.sub nests under it, and
      // its artifactId sub shares a path segment with that nested group.
      write("solo", "acme/solo", "dev.solo", ["solo", "sub"], "1.0.0");
      write("sub", "acme/sub", "dev.solo.sub", ["widget"], "1.0.0");
      const result = await generate(tree, output);
      expect(result.code, result.output).toBe(0);
      const rules = fs.readFileSync(path.join(output, "_redirects"), "utf8").split("\n").filter((line) => line.startsWith("/maven/"));
      const rule = (pattern: string, repository: string, version = ":version") =>
        "/maven/" + pattern + "/:file  https://github.com/" + repository + "/releases/download/v" + version + "/:file  302";
      expect(rules.sort()).toEqual([
        ...coreIds.map((id) => rule("dev/acme/" + id + "/:version", "acme/core")),
        rule("dev/acme/ui/:version", "acme/ui"),
        rule("dev/acme/ui-android/:version", "acme/ui"),
        rule("dev/acme/moved/1.0.0", "acme/old", "1.0.0"),
        rule("dev/acme/moved/2.0.0", "acme/new", "2.0.0"),
        rule("dev/solo/solo/:version", "acme/solo"),
        ...[".pom", ".jar", ".module", "-sources.jar"].map((extension) => "/maven/dev/solo/sub/1.0.0/sub-1.0.0" + extension
          + "  https://github.com/acme/solo/releases/download/v1.0.0/sub-1.0.0" + extension + "  302"),
        rule("dev/solo/sub/:artifact/:version", "acme/sub"),
      ].sort());
      expect(fs.existsSync(path.join(output, "maven/dev/solo/sub/widget/maven-metadata.xml"))).toBe(true);
    } finally { fs.rmSync(tree, { recursive: true, force: true }); }
  }, 120000);

  test("rejects a maven artifactId outside one path segment", async () => {
    const tree = fs.mkdtempSync(path.join(os.tmpdir(), "boring-registry-artifactid-"));
    const output = path.join(tree, "out");
    try {
      const repo = path.join(tree, "acme", "badid");
      fs.mkdirSync(path.join(repo, "1.0.0", "maven"), { recursive: true });
      fs.writeFileSync(path.join(repo, "README.md"), "# Bad Id\n");
      writeJson(path.join(repo, "1.0.0", "maven", "metadata.json"), {
        name: "badid", version: "1.0.0", groupId: "dev.acme",
        artifacts: [{ file: "badid-1.0.0.pom", url: "https://assets.example.test/badid-1.0.0.pom", artifactId: "a/b" }],
      });
      const result = await generate(tree, output);
      expect(result.code).not.toBe(0);
      expect(result.output.toLowerCase()).toContain("invalid artifactid");
    } finally { fs.rmSync(tree, { recursive: true, force: true }); }
  }, 120000);
});
