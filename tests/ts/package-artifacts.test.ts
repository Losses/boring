import { describe, expect, test } from "bun:test";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Feature spec 25: behind `package-artifacts=emit` the compiler packs
 * the recorded main-tree writes into the install artifact of the
 * target's ecosystem and writes it beside the output tree. The npm
 * tarball and the Kotlin Maven directory are build output: the pack
 * step compiles through the host tool a define names (`package-tsc`,
 * `package-kotlinc`) and forwards a failing tool's exit code and
 * output. The cargo crate, the Swift zip, and the Pub archive carry
 * source, because those registries install source.
 */

const REPO_ROOT = path.resolve(import.meta.dir, "../..");
const TSC = path.join(REPO_ROOT, "node_modules/typescript/bin/tsc");

interface CompilerOutcome {
  exitCode: number;
  stderr: string;
}

/** One package of the byte-identity check: its example, artifact path, and extra defines. */
type PackageIdentity = {
  hxml: string;
  file: string;
  extra: string[];
};

/**
 * Rewrites one example hxml for an artifact generation: every
 * reference tree path moves under `root`, and the artifact define is
 * appended. `extra` lines run after the rewrite for scenario defines.
 */
function rewriteHxml(name: string, root: string, extra: string[] = []): string {
  const source = fs.readFileSync(path.join(REPO_ROOT, "examples", name), "utf8");
  let out = source.replace(/reference\/[a-z0-9-]+(\/[a-z0-9-]+)*/g, (match) =>
    match.replace("reference", root),
  );
  out = out.replace("-D runtime-import=@boring/runtime", "-D runtime-import=./runtime");
  out = out.replace("-D package-shell=none\n", "");
  out += "-D package-artifacts=emit\n";
  for(const line of extra) {
    out += line + "\n";
  }
  return out;
}

/** Runs one rewritten generation and reports the compiler outcome. */
async function runHaxe(hxmlName: string, content: string): Promise<CompilerOutcome> {
  const hxmlPath = path.join(REPO_ROOT, "out", hxmlName);
  fs.mkdirSync(path.dirname(hxmlPath), { recursive: true });
  fs.writeFileSync(hxmlPath, content);
  const proc = Bun.spawn(["haxe", path.relative(REPO_ROOT, hxmlPath)], {
    cwd: REPO_ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
  return { exitCode, stderr };
}

function tempRoot(label: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), `boring-artifacts-${label}-`));
}

/** Lists a tar+gzip artifact's entries in archive order. */
async function tarList(artifact: string): Promise<string[]> {
  const proc = Bun.spawn(["tar", "-tzf", artifact], { stdout: "pipe", stderr: "pipe" });
  const [exitCode, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  expect(stderr).toBe("");
  expect(exitCode).toBe(0);
  return stdout.split("\n").filter(line => line.length > 0);
}

/** Reads one member of a tar+gzip artifact. */
function tarRead(artifact: string, member: string): string {
  const proc = Bun.spawnSync(["tar", "-xzOf", artifact, member]);
  expect(proc.stderr.toString()).toBe("");
  expect(proc.exitCode).toBe(0);
  return proc.stdout.toString();
}

/** Lists a zip artifact's entries in archive order. */
function zipList(artifact: string): string[] {
  const script = [
    "import sys, zipfile",
    "with zipfile.ZipFile(sys.argv[1]) as z:",
    "    for name in z.namelist():",
    "        print(name)",
  ].join("\n");
  const proc = Bun.spawnSync(["python3", "-c", script, artifact]);
  expect(proc.stderr.toString()).toBe("");
  expect(proc.exitCode).toBe(0);
  return proc.stdout.toString().split("\n").filter(line => line.length > 0);
}

// Every test here drives haxe/cargo/pub/tsc/kotlinc subprocess pipelines whose
// wall time scales with machine load; the explicit timeout raises only the
// harness patience for those subprocesses, never the asserted behavior.
describe("package artifact emission", () => {
  test("the npm tarball carries compiled JavaScript plus declarations and runs under plain node", async () => {
    const root = tempRoot("npm");
    try {
      const hxml = rewriteHxml("ts.hxml", root, [`-D package-tsc=${TSC}`]);
      const result = await runHaxe("package-artifacts-npm.hxml", hxml);
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);

      const artifact = path.join(root, "ts", "generated-0.1.0.tgz");
      expect(fs.existsSync(artifact)).toBe(true);
      const entries = await tarList(artifact);
      // Archive order is the sorted entry order the spec fixes.
      expect(entries).toEqual([...entries].sort());
      for(const entry of entries) {
        expect(entry.startsWith("package/")).toBe(true);
      }
      expect(entries).toContain("package/package.json");
      expect(entries).toContain("package/dist/runtime.js");
      expect(entries).toContain("package/dist/runtime.d.ts");
      expect(entries).toContain("package/dist/boring/Fp32.js");
      expect(entries).toContain("package/dist/boring/Fp32.d.ts");
      // The install unit is compiled output: no TypeScript source
      // ships, and the runtime test entry (node:fs for the test
      // harness) stays out of the package.
      expect(entries.filter(entry => entry.endsWith(".ts") && !entry.endsWith(".d.ts"))).toEqual([]);
      expect(entries).not.toContain("package/dist/runtime/test.js");
      expect(entries).not.toContain("package/_GeneratedFiles.txt");
      expect(entries.some(entry => entry.includes("gen-tests"))).toBe(false);
      const manifest = tarRead(artifact, "package/package.json");
      expect(manifest).toContain('"./runtime"');
      expect(manifest).toContain('"./dist/runtime.js"');
      expect(manifest).toContain('"./dist/runtime.d.ts"');

      // A registry consumer installs the tarball with the native CLI
      // and imports through the retargeted exports map. The consumer
      // runs under plain node: the whole point of the compile step is
      // that no TypeScript runtime is needed.
      const consumerRoot = path.join(root, "consumer");
      fs.mkdirSync(consumerRoot);
      fs.writeFileSync(path.join(consumerRoot, "package.json"), '{"name":"consumer","private":true}\n');
      const install = Bun.spawn(["npm", "install", "--no-audit", "--no-fund", artifact], {
        cwd: consumerRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      const [installCode, installErr] = await Promise.all([
        install.exited,
        new Response(install.stderr).text(),
      ]);
      expect(installErr).toBe("");
      expect(installCode).toBe(0);
      fs.writeFileSync(path.join(consumerRoot, "consumer.mjs"), [
        'import { Fp32 } from "generated/boring/Fp32";',
        'import { doubleToI64 } from "generated/runtime";',
        'if(Fp32.toBits(1.5) !== 0x3fc00000) { throw new Error("bad bits"); }',
        'if(doubleToI64(1.5).low !== 0) { throw new Error("bad runtime"); }',
        'console.log("tgz-consumer-ok");',
        "",
      ].join("\n"));
      const consumer = Bun.spawn(["node", "consumer.mjs"], {
        cwd: consumerRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      const [consumerCode, consumerOut, consumerErr] = await Promise.all([
        consumer.exited,
        new Response(consumer.stdout).text(),
        new Response(consumer.stderr).text(),
      ]);
      expect(consumerErr).toBe("");
      expect(consumerCode).toBe(0);
      expect(consumerOut.trim()).toBe("tgz-consumer-ok");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 120000);

  test("the cargo crate and the Pub archive keep the tree at the root", async () => {
    const rustRoot = tempRoot("rust");
    const dartRoot = tempRoot("dart");
    try {
      const rustResult = await runHaxe("package-artifacts-rust.hxml", rewriteHxml("rust.hxml", rustRoot));
      expect(rustResult.stderr).toBe("");
      expect(rustResult.exitCode).toBe(0);
      const crate = path.join(rustRoot, "rust-gen", "boring-codec-gen-0.1.0.crate");
      expect(fs.existsSync(crate)).toBe(true);
      const crateEntries = await tarList(crate);
      expect(crateEntries).toEqual([...crateEntries].sort());
      expect(crateEntries).toContain("Cargo.toml");
      expect(crateEntries).toContain("lib.rs");
      expect(crateEntries).not.toContain("_GeneratedFiles.txt");
      for(const entry of crateEntries) {
        expect(entry.startsWith("/")).toBe(false);
        expect(entry.startsWith("package/")).toBe(false);
      }

      const dartResult = await runHaxe("package-artifacts-dart.hxml", rewriteHxml("dart.hxml", dartRoot));
      expect(dartResult.stderr).toBe("");
      expect(dartResult.exitCode).toBe(0);
      const pubArchive = path.join(dartRoot, "dart", "generated-0.1.0.tar.gz");
      expect(fs.existsSync(pubArchive)).toBe(true);
      const pubEntries = await tarList(pubArchive);
      expect(pubEntries).toEqual([...pubEntries].sort());
      expect(pubEntries).toContain("pubspec.yaml");
      expect(pubEntries.some(entry => entry.startsWith("lib/"))).toBe(true);
      expect(pubEntries).not.toContain("_GeneratedFiles.txt");
    } finally {
      fs.rmSync(rustRoot, { recursive: true, force: true });
      fs.rmSync(dartRoot, { recursive: true, force: true });
    }
  }, 60_000);

  test("the Swift zip carries the tree at the root", async () => {
    const root = tempRoot("swift");
    try {
      const result = await runHaxe("package-artifacts-swift.hxml", rewriteHxml("swift.hxml", root));
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);
      const archive = path.join(root, "swift", "generated-0.1.0.zip");
      expect(fs.existsSync(archive)).toBe(true);
      const entries = zipList(archive);
      expect(entries).toEqual([...entries].sort());
      expect(entries).toContain("Package.swift");
      expect(entries).toContain("Runtime.swift");
      expect(entries.some(entry => entry.startsWith("boring/"))).toBe(true);
      expect(entries).not.toContain("_GeneratedFiles.txt");
      expect(entries.some(entry => entry.includes("gen-tests"))).toBe(false);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("the Kotlin target packs a Maven repository directory with a compiled jar", async () => {
    const root = tempRoot("kotlin");
    try {
      const hxml = rewriteHxml("kotlin.hxml", root, ["-D package-kotlinc=kotlinc", "-D package-group=dev.boring"]);
      const result = await runHaxe("package-artifacts-kotlin.hxml", hxml);
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);

      const versionDir = path.join(root, "kotlin", "maven", "dev", "boring", "generated", "0.1.0");
      const jar = path.join(versionDir, "generated-0.1.0.jar");
      const pom = path.join(versionDir, "generated-0.1.0.pom");
      expect(fs.existsSync(jar)).toBe(true);
      expect(fs.existsSync(pom)).toBe(true);
      const pomText = fs.readFileSync(pom, "utf8");
      expect(pomText).toContain("<groupId>dev.boring</groupId>");
      expect(pomText).toContain("<artifactId>generated</artifactId>");
      expect(pomText).toContain("<version>0.1.0</version>");
      expect(pomText).toContain("<artifactId>kotlin-stdlib</artifactId>");

      // The checksum files carry the sha1 of exactly the saved bytes.
      for(const file of [jar, pom]) {
        const expected = crypto.createHash("sha1").update(fs.readFileSync(file)).digest("hex");
        expect(fs.readFileSync(file + ".sha1", "utf8")).toBe(expected);
      }

      // The jar repacks the kotlinc classes through the fixed-date zip
      // writer, so its entry order and metadata hold the determinism
      // constants of the spec.
      const script = [
        "import sys, zipfile",
        "with zipfile.ZipFile(sys.argv[1]) as z:",
        "    names = z.namelist()",
        "    print('sorted', names == sorted(names))",
        "    print('dates', all(i.date_time == (2020, 6, 1, 12, 0, 0) for i in z.infolist()))",
        "    print('fp32', 'boring/Fp32.class' in names)",
      ].join("\n");
      const proc = Bun.spawnSync(["python3", "-c", script, jar]);
      expect(proc.stderr.toString()).toBe("");
      expect(proc.exitCode).toBe(0);
      expect(proc.stdout.toString()).toBe("sorted True\ndates True\nfp32 True\n");
      // No staging tree stays behind beside the output.
      expect(fs.existsSync(path.join(root, "kotlin", ".package-kotlinc-classes"))).toBe(false);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 240000);

  // Ten generations run here (one of them through kotlinc twice), so
  // the default five-second budget does not fit.
  test("two generations of the same inputs produce byte-identical artifacts", async () => {
    const first = tempRoot("identity-a");
    const second = tempRoot("identity-b");
    try {
      const packages: PackageIdentity[] = [
        {hxml: "ts.hxml", file: "ts/generated-0.1.0.tgz", extra: [`-D package-tsc=${TSC}`]},
        {hxml: "rust.hxml", file: "rust-gen/boring-codec-gen-0.1.0.crate", extra: []},
        {hxml: "swift.hxml", file: "swift/generated-0.1.0.zip", extra: []},
        {hxml: "dart.hxml", file: "dart/generated-0.1.0.tar.gz", extra: []},
        {hxml: "kotlin.hxml", file: "kotlin/maven/generated/generated/0.1.0/generated-0.1.0.jar", extra: ["-D package-kotlinc=kotlinc"]},
      ];
      for(const lane of packages) {
        const a = await runHaxe(`package-artifacts-id-a.hxml`, rewriteHxml(lane.hxml, first, lane.extra));
        expect(a.stderr).toBe("");
        expect(a.exitCode).toBe(0);
        const b = await runHaxe(`package-artifacts-id-b.hxml`, rewriteHxml(lane.hxml, second, lane.extra));
        expect(b.stderr).toBe("");
        expect(b.exitCode).toBe(0);
        expect(fs.readFileSync(path.join(second, lane.file))).toEqual(fs.readFileSync(path.join(first, lane.file)));
      }
    } finally {
      fs.rmSync(first, { recursive: true, force: true });
      fs.rmSync(second, { recursive: true, force: true });
    }
  }, 420000);

  test("an invalid package-artifacts value aborts the compile", async () => {
    const root = tempRoot("invalid");
    try {
      const hxml = rewriteHxml("ts.hxml", root).replace("-D package-artifacts=emit\n", "-D package-artifacts=bogus\n");
      const result = await runHaxe("package-artifacts-invalid.hxml", hxml);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package-artifacts accepts emit or none");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("artifacts without the package shell abort the compile", async () => {
    const root = tempRoot("conflict");
    try {
      // The repository's own ts.hxml carries the shell opt-out, so
      // only the path rewrite applies: shell none meets artifacts emit.
      const source = fs.readFileSync(path.join(REPO_ROOT, "examples", "ts.hxml"), "utf8");
      const hxml = source.replace(/reference\/[a-z0-9-]+(\/[a-z0-9-]+)*/g, (match) =>
        match.replace("reference", root),
      ) + "-D package-artifacts=emit\n";
      const result = await runHaxe("package-artifacts-conflict.hxml", hxml);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package artifacts require the package shell");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("npm artifacts without package-tsc abort the compile", async () => {
    const root = tempRoot("no-tsc");
    try {
      const result = await runHaxe("package-artifacts-no-tsc.hxml", rewriteHxml("ts.hxml", root));
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package artifacts on the TypeScript target require the TypeScript compiler");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("kotlin artifacts without package-kotlinc abort the compile", async () => {
    const root = tempRoot("no-kotlinc");
    try {
      const result = await runHaxe("package-artifacts-no-kotlinc.hxml", rewriteHxml("kotlin.hxml", root));
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package artifacts on the Kotlin target require the Kotlin compiler");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("a failing package-tsc forwards the exit code and the tool output", async () => {
    const root = tempRoot("tsc-fail");
    try {
      const hxml = rewriteHxml("ts.hxml", root, ["-D package-tsc=/bin/false"]);
      const result = await runHaxe("package-artifacts-tsc-fail.hxml", hxml);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package-tsc failed with exit code 1");
      expect(result.stderr).toContain("/bin/false");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("a failing package-kotlinc forwards the exit code and the tool output", async () => {
    const root = tempRoot("kotlinc-fail");
    try {
      const hxml = rewriteHxml("kotlin.hxml", root, ["-D package-kotlinc=/bin/false"]);
      const result = await runHaxe("package-artifacts-kotlinc-fail.hxml", hxml);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package-kotlinc failed with exit code 1");
      expect(result.stderr).toContain("/bin/false");
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);
});
