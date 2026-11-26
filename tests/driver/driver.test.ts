import { afterEach, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const entry = resolve("out/driver/driver.js");
const dirs: string[] = [];
type Fixture = { dir: string; file: string };
type RunResult = { code: number; output: string };

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function fixture(config: Record<string, unknown>): Fixture {
  const dir = mkdtempSync(join(tmpdir(), "boring-driver-"));
  dirs.push(dir);
  const file = join(dir, "boring.json");
  writeFileSync(file, JSON.stringify({ outRoot: "out", resultsDir: "results", baseline: "reference", sourceRoots: [], bundles: [
    { id: "reference", target: "ts" },
    { id: "header", target: "ts", test: false },
  ], ...config }));
  return { dir, file };
}

function run(file: string, args: string[], env: Record<string, string> = {}): RunResult {
  const result = Bun.spawnSync([process.execPath, entry, ...args, "--project", file], {
    cwd: resolve("."), env: { ...process.env, ...env }, stdout: "pipe", stderr: "pipe",
  });
  return { code: result.exitCode, output: result.stdout.toString() + result.stderr.toString() };
}

test("compare ignores configurations without tests and runs outside the boring checkout", () => {
  const { dir, file } = fixture({});
  mkdirSync(join(dir, "results"));
  writeFileSync(join(dir, "results", "reference.jsonl"), '{"id":"same","name":"same","verdict":"pass"}\n');
  const result = run(file, ["compare"]);
  expect(result.code).toBe(0);
  expect(result.output).toContain("All 1 targets (reference)");
  expect(result.output).not.toContain("header.jsonl");
});

test("compare reports a verdict mismatch", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" }, { id: "other", target: "ts" },
  ] });
  mkdirSync(join(dir, "results"));
  writeFileSync(join(dir, "results", "reference.jsonl"), '{"id":"same","name":"same","verdict":"pass"}\n');
  writeFileSync(join(dir, "results", "other.jsonl"), '{"id":"same","name":"same","verdict":"fail"}\n');
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain("Verdict mismatch on same");
});

test("compare excludes a tested configuration marked compare=false", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" }, { id: "alternate", target: "ts", compare: false },
  ] });
  mkdirSync(join(dir, "results"));
  writeFileSync(join(dir, "results", "reference.jsonl"), '{"id":"same","name":"same","verdict":"pass"}\n');
  const result = run(file, ["compare"]);
  expect(result.code).toBe(0);
  expect(result.output).toContain("All 1 targets (reference)");
  expect(result.output).not.toContain("alternate.jsonl");
});

test("baseline must participate in compare", () => {
  const { file } = fixture({ bundles: [{ id: "reference", target: "ts", compare: false }] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('baseline "reference" must participate in compare');
});

test("a configuration cannot compare results without tests", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts" }, { id: "header", target: "ts", test: false, compare: true },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "header": compare=true requires test=true');
});

test("explicit test rejects a configuration marked test=false", () => {
  const { file } = fixture({});
  const result = run(file, ["test", "header"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain("test=false");
});

test("baseline must have tests", () => {
  const { file } = fixture({ baseline: "header" });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('baseline "header" must have tests');
});

test("gen runs afterGen with the project as working directory", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts", afterGen: { command: process.execPath, args: ["write-marker.ts"] } },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  writeFileSync(fakeHaxe, "#!/bin/sh\nexit 0\n");
  chmodSync(fakeHaxe, 0o755);
  writeFileSync(join(dir, "write-marker.ts"), 'await Bun.write("marker.txt", "generated");\n');
  const result = run(file, ["gen", "reference"], { PATH: bin + ":" + process.env.PATH });
  expect(result.code).toBe(0);
  expect(readFileSync(join(dir, "marker.txt"), "utf8")).toBe("generated");
});

test("pack runs the maven publication command with the substituted output directory", () => {
  const current = fixture({ bundles: [
    { id: "reference", target: "kotlin", package: { name: "engine", version: "1.0.0" } },
  ] });
  const { dir, file } = current;
  const project = JSON.parse(readFileSync(file, "utf8"));
  project.bundles[0].mavenPublication = { command: process.execPath, args: [join(dir, "publish.ts"), "{maven}", "{version}"], env: { PROBE_VERSION: "{version}" } };
  writeFileSync(file, JSON.stringify(project));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  writeFileSync(fakeHaxe, "#!/bin/sh\nexit 0\n");
  chmodSync(fakeHaxe, 0o755);
  writeFileSync(join(dir, "publish.ts"),
    'import { writeFileSync } from "node:fs";\nwriteFileSync(process.argv[2] + "/probe.txt", [process.argv[2], process.argv[3], process.env.PROBE_VERSION].join("|"));\n');
  const result = run(file, ["pack", "reference"], { PATH: bin + ":" + process.env.PATH });
  expect(result.code, result.output).toBe(0);
  const mavenDir = join(dir, "out", "reference", "maven");
  expect(readFileSync(join(mavenDir, "probe.txt"), "utf8")).toBe(mavenDir + "|1.0.0|1.0.0");
});

test("pack retries a kmp publication whose Gradle repository lookup fails, then publishes", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "kotlin", package: { name: "engine", version: "1.0.0" }, kmpPublication: true },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  writeFileSync(fakeHaxe, "#!/bin/sh\nexit 0\n");
  chmodSync(fakeHaxe, 0o755);
  const publication = join(dir, "publication");
  mkdirSync(join(publication, "gradle", "wrapper"), { recursive: true });
  writeFileSync(join(publication, "settings.gradle.kts"), "");
  const attempts = join(dir, "attempts");
  writeFileSync(join(publication, "gradlew"), `#!/bin/sh
set -u
n=$(cat "$ATTEMPTS_FILE" 2>/dev/null || echo 0)
n=$((n+1))
echo "$n" > "$ATTEMPTS_FILE"
if [ "$n" -le "$FAIL_FIRST" ]; then
  echo "Plugin [id: 'org.jetbrains.kotlin.multiplatform', version: '2.3.20', apply: false] was not found in any of the following sources:" >&2
  echo "- Plugin Repositories (could not resolve plugin artifact 'org.jetbrains.kotlin.multiplatform:org.jetbrains.kotlin.multiplatform.gradle.plugin:2.3.20')" >&2
  exit 1
fi
for a in "$@"; do
  case "$a" in
    -PmavenDir=*) maven="\${a#-PmavenDir=}" ;;
  esac
done
mkdir -p "$maven/org/example/engine/1.0.0"
printf '<project/>' > "$maven/org/example/engine/1.0.0/engine-1.0.0.pom"
`);
  chmodSync(join(publication, "gradlew"), 0o755);
  const env = { PATH: bin + ":" + process.env.PATH, BORING_PUBLICATION_PROJECT: publication, ATTEMPTS_FILE: attempts, FAIL_FIRST: "1" };
  const retried = run(file, ["pack", "reference"], env);
  expect(retried.code, retried.output).toBe(0);
  expect(retried.output).toContain("could not resolve the build plugins or dependencies");
  expect(retried.output).toContain("kmpPublication passed on attempt 2");
  expect(readFileSync(attempts, "utf8").trim()).toBe("2");
  const pom = join(dir, "out", "reference", "maven", "org", "example", "engine", "1.0.0", "engine-1.0.0.pom");
  expect(readFileSync(pom, "utf8")).toBe("<project/>");
  // A repository failure that does not clear keeps the step's standard report after the last attempt.
  rmSync(attempts, { force: true });
  const failed = run(file, ["pack", "reference"], { ...env, FAIL_FIRST: "99" });
  expect(failed.code).toBe(1);
  expect(failed.output).toContain('step "kmpPublication" failed with exit code 1');
  expect(failed.output.split("could not resolve the build plugins").length - 1).toBe(2);
  expect(readFileSync(attempts, "utf8").trim()).toBe("3");
}, 30000);

test("gen does not run the maven publication command", () => {
  const current = fixture({ bundles: [
    { id: "reference", target: "kotlin" },
  ] });
  const { dir, file } = current;
  const project = JSON.parse(readFileSync(file, "utf8"));
  project.bundles[0].mavenPublication = { command: process.execPath, args: [join(dir, "publish.ts"), "{maven}"] };
  writeFileSync(file, JSON.stringify(project));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  writeFileSync(fakeHaxe, "#!/bin/sh\nexit 0\n");
  chmodSync(fakeHaxe, 0o755);
  writeFileSync(join(dir, "publish.ts"),
    'import { writeFileSync } from "node:fs";\nwriteFileSync(process.argv[2] + "/probe.txt", process.argv[2]);\n');
  const result = run(file, ["gen", "reference"], { PATH: bin + ":" + process.env.PATH });
  expect(result.code, result.output).toBe(0);
  expect(readdirSync(join(dir, "out", "reference")).includes("maven")).toBe(false);
});

test("verify with pack ignores configurations without package metadata", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" },
    { id: "header", target: "ts", test: false },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");
  const generated = `import { test } from "bun:test";
import { appendFileSync } from "node:fs";
test("same", () => appendFileSync(process.env.BORING_TEST_RESULTS!,
  JSON.stringify({ id: "same", name: "same", verdict: "pass" }) + "\\n"));
`;
  writeFileSync(fakeHaxe, `#!/usr/bin/env bun
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
const output = args.find((arg) => arg.startsWith("ts-test-output="))?.slice("ts-test-output=".length);
if (output) {
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, "driver.test.ts"), ${JSON.stringify(generated)});
}
`);
  chmodSync(fakeHaxe, 0o755);
  const result = run(file, ["verify", "--with-pack"], { PATH: bin + ":" + process.env.PATH });
  expect(result.code).toBe(0);
  expect(result.output).toContain("All 1 targets (reference)");
  expect(result.output).not.toContain("[pack]");
});

test("run.env cannot replace the driver's results file", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", run: { env: { BORING_TEST_RESULTS: "wrong.jsonl" } } },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "reference": run.env may not set BORING_TEST_RESULTS');
});

test("pack passes the declared license to the compiler", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts", package: { name: "demo", version: "1.0.0", license: "MPL-2.0" } },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "haxe"), '#!/bin/sh\nprintf "%s\\n" "$@" > "$BORING_ARG_LOG"\n');
  writeFileSync(join(bin, "tsc"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "haxe"), 0o755);
  chmodSync(join(bin, "tsc"), 0o755);
  const argLog = join(dir, "haxe-args.txt");
  const result = run(file, ["pack", "reference"], { PATH: bin + ":" + process.env.PATH, BORING_ARG_LOG: argLog });
  expect(result.code).toBe(0);
  expect(readFileSync(argLog, "utf8").split("\n")).toContain("package-license=MPL-2.0");
});

test("package license must be a nonempty string when declared", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", package: { name: "demo", version: "1.0.0", license: "" } },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "reference": package license must not be empty');
});

test("sourceSet compiles listed types and direct package members", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: { core: { packages: ["demo"], types: ["Named"],
      discover: [{ root: "src", packages: ["demo"], suffix: "Test" }] } },
    bundles: [{ id: "reference", target: "haxe", sourceSet: "core", rootsFile: "classes.hxml",
      haxeArgs: ["-js", "out/main.js", "--dce", "no"] }],
  });
  mkdirSync(join(dir, "src", "demo", "nested"), { recursive: true });
  writeFileSync(join(dir, "src", "Named.hx"), "class Named { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Direct.hx"), "package demo; class Direct { public static function value():Int return 2; }\n");
  writeFileSync(join(dir, "src", "demo", "ZTest.hx"), "package demo; class ZTest { public static function value():Int return 4; }\n");
  writeFileSync(join(dir, "src", "demo", "ATest.hx"), "package demo; class ATest { public static function value():Int return 5; }\n");
  writeFileSync(join(dir, "src", "demo", "nested", "Nested.hx"), "package demo.nested; class Nested { public static function value():Int return 3; }\n");
  const rootsFile = join(dir, "classes.hxml");
  writeFileSync(rootsFile, "stale\n");
  const roots = run(file, ["roots", "core", "--output", "classes.hxml"]);
  expect(roots.code).toBe(0);
  expect(readFileSync(rootsFile, "utf8")).toBe("--macro haxe.macro.Compiler.include('demo', false, null, null, true)\nNamed\ndemo.ATest\ndemo.ZTest\n");
  expect(readdirSync(dir).filter((name) => name.startsWith("classes.hxml.tmp-"))).toEqual([]);
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(0);
  const output = readFileSync(join(dir, "out", "main.js"), "utf8");
  expect(output).toContain("Named");
  expect(output).toContain("demo_Direct");
  expect(output).toContain("demo_ATest");
  expect(output).not.toContain("demo_nested_Nested");
});

test("sourceSet rejects an unknown name", () => {
  const { file } = fixture({ bundles: [{ id: "reference", target: "ts", sourceSet: "missing" }] });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('bundle "reference": unknown source set "missing"');
});

test("sourceSet discovery rejects an empty matching directory", () => {
  const { dir, file } = fixture({
    sourceSets: { core: { discover: [{ root: "src", packages: ["demo"], suffix: "Test" }] } },
    bundles: [{ id: "reference", target: "ts", sourceSet: "core" }],
  });
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Helper.hx"), "package demo; class Helper {}\n");
  const result = run(file, ["roots", "core", "--output", "classes.hxml"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('source set "core": no modules ending in "Test"');
  expect(readdirSync(dir).filter((name) => name.startsWith("classes.hxml"))).toEqual([]);
});


test("verify continues after a bundle test failure, aggregates and runs remaining bundles", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts" },
    { id: "other", target: "ts" },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const fakeHaxe = join(bin, "haxe");

  // Test that passes normally (writes a pass verdict)
  const passTest = 'import { test } from "bun:test";\n' +
    'import { appendFileSync } from "node:fs";\n' +
    'test("pass", () => appendFileSync(process.env.BORING_TEST_RESULTS!,' +
    '  JSON.stringify({ id: "pass", name: "pass", verdict: "pass" }) + "\\n"));\n';

  // Test that always fails (throws)
  const failTest = 'import { test } from "bun:test";\n' +
    'test("fail", () => { throw new Error("deliberate failure"); });\n';

  writeFileSync(fakeHaxe, '#!/usr/bin/env bun\n' +
    'import { mkdirSync, writeFileSync } from "node:fs";\n' +
    'import { join } from "node:path";\n' +
    'const args = process.argv.slice(2);\n' +
    'const output = args.find((arg) => arg.startsWith("ts-test-output="))?.slice("ts-test-output=".length);\n' +
    'if (output) {\n' +
    '  mkdirSync(output, { recursive: true });\n' +
    '  if (output.includes("reference")) {\n' +
    '    writeFileSync(join(output, "driver.test.ts"), ' + JSON.stringify(failTest) + ');\n' +
    '  } else {\n' +
    '    writeFileSync(join(output, "driver.test.ts"), ' + JSON.stringify(passTest) + ');\n' +
    '  }\n' +
    '}\n');
  chmodSync(fakeHaxe, 0o755);

  const result = run(file, ["verify"], { PATH: bin + ":" + process.env.PATH });

  // Exit code is non-zero because reference failed
  expect(result.code).toBe(1);

  // The aggregate report is printed, including the per-bundle first error
  expect(result.output).toContain("--- aggregate report:");
  expect(result.output).toContain("bundle(s) failed");
  expect(result.output).toContain("reference");
  expect(result.output).toContain("first error:");

  // The other bundle's test did run (its results file exists)
  // and contains the pass verdict
  const otherResults = join(dir, "results", "other.jsonl");
  expect(readFileSync(otherResults, "utf8")).toContain('"verdict":"pass"');
});


test("pack passes the package name of the bundle's own ecosystem", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts", package: { name: "tiqian-engine", version: "1.0.0", npmName: "@tiqian/engine" } },
    { id: "shared", target: "ts", package: { name: "tiqian-shared", version: "1.0.0" } },
    { id: "protocol-rust", target: "rust", package: { name: "tiqian-protocol", version: "1.0.0", cargoName: "tiqian_protocol_crate" } },
    { id: "protocol-dart", target: "dart", package: { name: "tiqian-protocol", version: "1.0.0", pubName: "tiqian_protocol_pkg" } },
    { id: "protocol-kotlin", target: "kotlin", mavenPublication: { command: process.execPath, args: ["-e", ""] },
      package: { name: "tiqian-protocol", version: "1.0.0", mavenName: "tiqian-protocol-maven" } },
  ] });
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "haxe"), '#!/bin/sh\nprintf "%s\\n" "$@" >> "$BORING_ARG_LOG"\n');
  writeFileSync(join(bin, "tsc"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "haxe"), 0o755);
  chmodSync(join(bin, "tsc"), 0o755);
  const argLog = join(dir, "haxe-args.txt");
  const result = run(file, ["pack", "reference", "shared", "protocol-rust", "protocol-dart", "protocol-kotlin"],
    { PATH: bin + ":" + process.env.PATH, BORING_ARG_LOG: argLog });
  expect(result.code, result.output).toBe(0);
  const args = readFileSync(argLog, "utf8").split("\n");
  expect(args).toContain("package-name=@tiqian/engine");
  expect(args).toContain("package-name=tiqian-shared");
  expect(args).toContain("package-name=tiqian_protocol_crate");
  expect(args).toContain("package-name=tiqian_protocol_pkg");
  expect(args).toContain("package-name=tiqian-protocol-maven");
  expect(args).not.toContain("package-name=tiqian-protocol");
});

test("an empty ecosystem package name is rejected", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", package: { name: "demo", version: "1.0.0", npmName: "" } },
  ] });
  const result = run(file, ["compare"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('field "npmName" must not be empty');
});

function dependsFixture(dependsOn: string[], dependency: Record<string, unknown>) {
  return fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn },
    { id: "base", target: "ts", test: false, package: { name: "demo-base", version: "1.0.0" }, ...dependency },
  ] });
}

test("dependsOn names an unknown bundle", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn: ["missing"] },
  ] });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('dependsOn names unknown bundle "missing"');
});

test("dependsOn may not name its own bundle", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn: ["reference"] },
  ] });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain("may not name the bundle itself");
});

test("dependsOn lists a bundle twice", () => {
  const { file } = dependsFixture(["base", "base"], {});
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('lists "base" twice');
});

test("dependsOn requires the same target", () => {
  const { file } = dependsFixture(["base"], { target: "rust" });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('dependsOn "base" has target "rust", expected "ts"');
});

test("dependsOn requires the dependency package", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn: ["base"] },
    { id: "base", target: "ts", test: false },
  ] });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('dependsOn "base" declares no package');
});

test("dependsOn rejects a cycle", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn: ["base"], package: { name: "demo", version: "1.0.0" } },
    { id: "base", target: "ts", test: false, dependsOn: ["reference"], package: { name: "demo-base", version: "1.0.0" } },
  ] });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain("dependsOn forms a cycle");
});

test("a valid dependsOn parses", () => {
  const { file } = dependsFixture(["base"], {});
  const result = run(file, ["compare"]);
  expect(result.output).not.toContain("dependsOn");
});

test("dependsOn passes a dependency module file to the compiler", () => {
  const { dir, file } = fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn: ["base"] },
    { id: "base", target: "ts", test: false, package: { name: "base-pkg", version: "1.0.0" } },
  ] });
  mkdirSync(join(dir, "out", "base"), { recursive: true });
  writeFileSync(join(dir, "out", "base", "modules.txt"), "org.demo.Base\n");
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "haxe"), '#!/bin/sh\nprintf "%s\\n" "$@" > "$BORING_ARG_LOG"\n');
  chmodSync(join(bin, "haxe"), 0o755);
  const argLog = join(dir, "haxe-args.txt");
  const result = run(file, ["gen", "reference"], { PATH: bin + ":" + process.env.PATH, BORING_ARG_LOG: argLog });
  expect(result.code).toBe(0);
  expect(readFileSync(argLog, "utf8")).toContain("package-dependency-file=");
  expect(readFileSync(join(dir, "out", "reference", "dependencies.tsv"), "utf8")).toBe("org.demo.Base\tbase-pkg\n");
});

test("dependsOn requires the dependency to be generated first", () => {
  const { file } = fixture({ bundles: [
    { id: "reference", target: "ts", dependsOn: ["base"] },
    { id: "base", target: "ts", test: false, package: { name: "base-pkg", version: "1.0.0" } },
  ] });
  const result = run(file, ["gen", "reference"]);
  expect(result.code).toBe(1);
  expect(result.output).toContain('dependsOn "base" has no module manifest; run gen for "base" first');
});



test("dependsOn skips provided modules and imports the dependency package", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "ts", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer-pkg", version: "1.0.0" } },
      { id: "base", target: "ts", sourceSet: "base", test: false, compare: false, package: { name: "base-pkg", version: "1.0.0" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/ts/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/ts"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "tscompiler.Compiler.use()",
    "-D", "runtime-import=./runtime", "-D", "runtime-emit=.", "-D", "package-shell=none",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const consumer = run(file, ["gen", "consumer"]);
  if (consumer.code !== 0) throw new Error(consumer.output);
  expect(readFileSync(join(dir, "out", "base", "modules.txt"), "utf8")).toContain("demo.Base");
  const generated = readFileSync(join(dir, "out", "consumer", "gen", "demo", "Consumer.ts"), "utf8");
  expect(generated).toContain('from "base-pkg/demo/Base"');
  expect(readdirSync(join(dir, "out", "consumer", "gen", "demo"))).not.toContain("Base.ts");
}, 30000);

test("dependsOn skips provided modules and imports the Rust crate", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "rust", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer-pkg", version: "1.0.0" } },
      { id: "base", target: "rust", sourceSet: "base", test: false, compare: false, package: { name: "base-pkg", version: "1.0.0" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/rust/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/rust"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "rustcompiler.Compiler.use()",
    "-D", "runtime-import=crate::runtime", "-D", "runtime-emit=runtime",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const consumer = run(file, ["gen", "consumer"]);
  if (consumer.code !== 0) throw new Error(consumer.output);
  expect(readFileSync(join(dir, "out", "base", "modules.txt"), "utf8")).toContain("demo.Base");
  expect(readFileSync(join(dir, "out", "consumer", "gen", "demo", "consumer.rs"), "utf8")).toContain("use base_pkg::demo::base::Base;");
  expect(readdirSync(join(dir, "out", "consumer", "gen", "demo"))).not.toContain("base.rs");
}, 30000);

test("dependsOn skips provided modules on the Kotlin target", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "kotlin", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer-pkg", version: "1.0.0" } },
      { id: "base", target: "kotlin", sourceSet: "base", test: false, compare: false, package: { name: "base-pkg", version: "1.0.0" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/kotlin/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/kotlin"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "kotlincompiler.Compiler.use()",
    "-D", "kotlin_emit_origins", "-D", "runtime-import=boring.runtime", "-D", "runtime-emit=runtime",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const consumer = run(file, ["gen", "consumer"]);
  if (consumer.code !== 0) throw new Error(consumer.output);
  expect(readFileSync(join(dir, "out", "base", "modules.txt"), "utf8")).toContain("demo.Base");
  expect(readdirSync(join(dir, "out", "consumer", "gen", "demo"))).not.toContain("Base.kt");
  expect(readdirSync(join(dir, "out", "consumer", "gen", "demo"))).toContain("Consumer.kt");
}, 30000);

test("dependsOn skips provided modules and imports the Dart package", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "dart", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer-pkg", version: "1.0.0" } },
      { id: "base", target: "dart", sourceSet: "base", test: false, compare: false, package: { name: "base-pkg", version: "1.0.0" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/dart/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/dart"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "dartcompiler.Compiler.use()",
    "-D", "runtime-import=@boring/runtime", "-D", "runtime-emit=.",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const consumer = run(file, ["gen", "consumer"]);
  if (consumer.code !== 0) throw new Error(consumer.output);
  expect(readFileSync(join(dir, "out", "base", "modules.txt"), "utf8")).toContain("demo.Base");
  expect(readdirSync(join(dir, "out", "consumer", "gen", "lib", "demo"))).not.toContain("base.dart");
  expect(readFileSync(join(dir, "out", "consumer", "gen", "lib", "demo", "consumer.dart"), "utf8")).toContain("package:base-pkg/demo/base.dart");
}, 30000);

test("dependsOn skips provided modules and imports the Swift module", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "swift", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer-pkg", version: "1.0.0" } },
      { id: "base", target: "swift", sourceSet: "base", test: false, compare: false, package: { name: "base-pkg", version: "1.0.0" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/swift/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/swift"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "swiftcompiler.Compiler.use()",
    "-D", "runtime-import=Runtime", "-D", "runtime-emit=.",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const consumer = run(file, ["gen", "consumer"]);
  if (consumer.code !== 0) throw new Error(consumer.output);
  expect(readFileSync(join(dir, "out", "base", "modules.txt"), "utf8")).toContain("demo.Base");
  expect(readdirSync(join(dir, "out", "consumer", "gen", "demo"))).not.toContain("Base.swift");
  expect(readFileSync(join(dir, "out", "consumer", "gen", "demo", "Consumer.swift"), "utf8")).toContain("import base_pkg");
}, 30000);

test("pack writes declared dependencies into the package manifest", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "ts", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer", npmName: "consumer-pkg", version: "2.0.0" } },
      { id: "base", target: "ts", sourceSet: "base", test: false, compare: false, package: { name: "base", npmName: "base-pkg", version: "1.2.3" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/ts/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/ts"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "tscompiler.Compiler.use()",
    "-D", "runtime-import=./runtime", "-D", "runtime-emit=.",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const bin = join(dir, "bin");
  mkdirSync(bin, { recursive: true });
  const tsc = join(bin, "tsc");
  writeFileSync(tsc, "#!/bin/sh\nstage=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-p\" ]; then stage=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nif [ -n \"$stage\" ]; then mkdir -p \"$stage/dist\"; fi\nexit 0\n");
  chmodSync(tsc, 0o755);
  const consumer = run(file, ["pack", "consumer"], { BORING_PACKAGE_TSC: tsc });
  if (consumer.code !== 0) throw new Error(consumer.output);
  const manifest = JSON.parse(readFileSync(join(dir, "out", "consumer", "gen", "package.json"), "utf8"));
  expect(manifest.dependencies).toEqual({ "base-pkg": "1.2.3" });
}, 30000);

test("gen writes declared Rust dependencies into Cargo.toml", () => {
  const { dir, file } = fixture({
    sourceRoots: ["src"],
    sourceSets: {
      base: { types: ["demo.Base"] },
      consumer: { types: ["demo.Consumer"] },
    },
    baseline: "consumer",
    bundles: [
      { id: "consumer", target: "rust", sourceSet: "consumer", dependsOn: ["base"], package: { name: "consumer-pkg", version: "2.0.0" } },
      { id: "base", target: "rust", sourceSet: "base", test: false, compare: false, package: { name: "base-pkg", version: "1.2.3" } },
    ],
  });
  const repo = resolve(".");
  const compilerArgs = [
    "-lib", "reflaxe",
    "-cp", join(repo, "packages/compiler"),
    "-cp", join(repo, "samples"),
    "-cp", join(repo, "packages/compiler/reflaxe/rust/std-shadow"),
    "-cp", join(repo, "packages/compiler/reflaxe/rust"),
    "--macro", 'Intercept.run(["src"])',
    "--macro", "haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro", "rustcompiler.Compiler.use()",
    "-D", "runtime-import=crate::runtime", "-D", "runtime-emit=runtime",
  ];
  const config = JSON.parse(readFileSync(file, "utf8"));
  for (const bundle of config.bundles) bundle.haxeArgs = compilerArgs;
  writeFileSync(file, JSON.stringify(config));
  mkdirSync(join(dir, "src", "demo"), { recursive: true });
  writeFileSync(join(dir, "src", "demo", "Base.hx"), "package demo; class Base { public static function value():Int return 1; }\n");
  writeFileSync(join(dir, "src", "demo", "Consumer.hx"), "package demo; class Consumer { public static function value():Int return Base.value(); }\n");
  const base = run(file, ["gen", "base"]);
  if (base.code !== 0) throw new Error(base.output);
  const consumer = run(file, ["gen", "consumer"]);
  if (consumer.code !== 0) throw new Error(consumer.output);
  const manifest = readFileSync(join(dir, "out", "consumer", "gen", "Cargo.toml"), "utf8");
  expect(manifest).toContain("[dependencies]");
  expect(manifest).toContain('base_pkg = "1.2.3"');
}, 30000);
