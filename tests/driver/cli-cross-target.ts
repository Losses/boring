import { chmodSync, cpSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

type CommandResult = { code: number; output: string };

const root = resolve(".");
const fixture = mkdtempSync(join(tmpdir(), "boring-driver-cli-"));
cpSync(resolve("tests/driver/fixtures/compare"), fixture, { recursive: true });
const project = join(fixture, "boring.json");
const verifyRoot = join(fixture, "verify");
const toolbin = join(fixture, "toolbin");
const afterGenLog = join(fixture, "after-gen.log");
mkdirSync(verifyRoot);
mkdirSync(toolbin);
mkdirSync(join(verifyRoot, "src", "demo"), { recursive: true });
writeFileSync(join(verifyRoot, "src", "demo", "ZTest.hx"), "package demo; class ZTest {}\n");
writeFileSync(join(verifyRoot, "src", "demo", "ATest.hx"), "package demo; class ATest {}\n");
writeFileSync(join(verifyRoot, "src", "demo", "Helper.hx"), "package demo; class Helper {}\n");
writeFileSync(join(verifyRoot, "boring.json"), JSON.stringify({
  outRoot: "out", resultsDir: "results", baseline: "only", sourceRoots: ["src"],
  sourceSets: { core: { types: ["demo.Helper"], discover: [{ root: "src", packages: ["demo"], suffix: "Test" }] } },
  bundles: [{ id: "only", target: "ts", sourceSet: "core", package: { name: "demo", version: "1.0.0" },
    afterGen: { command: "postgen" } }],
}));
for (const name of ["haxe", "tsc"]) {
  const path = join(toolbin, name);
  writeFileSync(path, "#!/usr/bin/env sh\nexit 0\n");
  chmodSync(path, 0o755);
}
const bunStub = join(toolbin, "bun");
writeFileSync(bunStub, "#!/usr/bin/env sh\nif [ \"$1\" = test ]; then printf '{\"id\":\"smoke\",\"name\":\"smoke\",\"verdict\":\"pass\"}\\n' > \"$BORING_TEST_RESULTS\"; fi\n");
chmodSync(bunStub, 0o755);
const postgen = join(toolbin, "postgen");
writeFileSync(postgen, "#!/usr/bin/env sh\nprintf 'ran\\n' >> \"$BORING_AFTER_GEN_LOG\"\n");
chmodSync(postgen, 0o755);
const fakeToolsEnv = { ...process.env, PATH: `${toolbin}:${process.env.PATH ?? ""}`, BORING_AFTER_GEN_LOG: afterGenLog };

function command(program: string, args: string[], env: NodeJS.ProcessEnv = process.env): CommandResult {
  const result = Bun.spawnSync([program, ...args], {
    cwd: root,
    env,
    stdout: "pipe",
    stderr: "pipe",
  });
  const output = result.stdout.toString() + result.stderr.toString();
  if (result.exitCode !== 0) {
    throw new Error(`${program} ${args.join(" ")} failed (${result.exitCode}):\n${output}`);
  }
  return { code: result.exitCode, output };
}

function sources(directory: string, suffix: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...sources(path, suffix));
    else if (entry.name.endsWith(`.${suffix}`)) files.push(path);
  }
  return files.sort();
}

function compare(program: string, args: string[]): string {
  const output = command(program, [...args, "compare", "--project", project]).output;
  const start = output.indexOf("[compare]");
  const end = output.indexOf("bundle driver: ok", start);
  if (start < 0 || end < 0) {
    throw new Error(`${program} did not complete the comparison:\n${output}`);
  }
  // Cargo may write its own warnings to stderr. Compare the driver's full
  // report, including any diagnostic between its header and success line.
  return output.slice(start, end + "bundle driver: ok".length).trim();
}

function verify(program: string, args: string[]): string {
  writeFileSync(afterGenLog, "");
  const output = command(program, [...args, "verify", "--with-pack", "--project", join(verifyRoot, "boring.json")], fakeToolsEnv).output;
  const start = output.indexOf("[gen]");
  const end = output.indexOf("bundle driver: ok", start);
  if (start < 0 || end < 0 || !output.includes("[test]") || !output.includes("[compare]") || !output.includes("[pack]")) {
    throw new Error(`${program} did not complete verification:\n${output}`);
  }
  if (readFileSync(afterGenLog, "utf8") !== "ran\nran\n") {
    throw new Error(`${program} did not run afterGen for gen and pack`);
  }
  // Keep every driver line, including failures and command plans; discard only
  // toolchain warnings emitted outside the driver's report.
  return output.slice(start, end + "bundle driver: ok".length).trim();
}

function roots(program: string, args: string[]): string {
  const outputPath = join(verifyRoot, "classes.hxml");
  writeFileSync(outputPath, "stale\n");
  const output = command(program, [...args, "roots", "core", "--project", join(verifyRoot, "boring.json"),
    "--output", outputPath]).output;
  if (!output.includes("bundle driver: ok")) throw new Error(`${program} did not complete roots generation:\n${output}`);
  const contents = readFileSync(outputPath, "utf8");
  if (contents !== "demo.ATest\ndemo.Helper\ndemo.ZTest\n") {
    throw new Error(`${program} wrote unexpected roots:\n${contents}`);
  }
  if (readdirSync(verifyRoot).some((name) => name.startsWith("classes.hxml.tmp-"))) {
    throw new Error(`${program} left a roots temporary file`);
  }
  return contents;
}

try {
  const outputs: string[] = [];
  const verifications: string[] = [];
  const rootFiles: string[] = [];

  command("haxe", ["packages/driver/driver.hxml"]);
  outputs.push(compare(process.execPath, ["out/driver/driver.js"]));
  verifications.push(verify(process.execPath, ["out/driver/driver.js"]));
  rootFiles.push(roots(process.execPath, ["out/driver/driver.js"]));
  process.stdout.write("haxe-js: CLI comparison and verification passed\n");

  command("haxe", ["packages/driver/ts.hxml"]);
  outputs.push(compare(process.execPath, ["packages/driver/launchers/ts.ts"]));
  verifications.push(verify(process.execPath, ["packages/driver/launchers/ts.ts"]));
  rootFiles.push(roots(process.execPath, ["packages/driver/launchers/ts.ts"]));
  process.stdout.write("ts: CLI comparison passed\n");

  command("haxe", ["packages/driver/kotlin.hxml"]);
  command("kotlinc", ["-nowarn", ...sources("out/driver/kotlin/gen", "kt"),
    "packages/driver/launchers/KotlinMain.kt", "-include-runtime", "-d", "out/driver/kotlin/driver.jar"]);
  outputs.push(compare("java", ["-jar", "out/driver/kotlin/driver.jar"]));
  verifications.push(verify("java", ["-jar", "out/driver/kotlin/driver.jar"]));
  rootFiles.push(roots("java", ["-jar", "out/driver/kotlin/driver.jar"]));
  process.stdout.write("kotlin: CLI comparison passed\n");

  command("haxe", ["packages/driver/rust.hxml"]);
  outputs.push(compare("cargo", ["run", "--quiet", "--manifest-path", "packages/driver/rust-launcher/Cargo.toml", "--"]));
  verifications.push(verify("cargo", ["run", "--quiet", "--manifest-path", "packages/driver/rust-launcher/Cargo.toml", "--"]));
  rootFiles.push(roots("cargo", ["run", "--quiet", "--manifest-path", "packages/driver/rust-launcher/Cargo.toml", "--"]));
  process.stdout.write("rust: CLI comparison passed\n");

  command("haxe", ["packages/driver/swift.hxml"]);
  command("swiftc", [...sources("out/driver/swift/gen", "swift"),
    "packages/driver/launchers/SwiftMain.swift", "-o", "out/driver/swift/driver"]);
  outputs.push(compare("out/driver/swift/driver", []));
  verifications.push(verify("out/driver/swift/driver", []));
  rootFiles.push(roots("out/driver/swift/driver", []));
  process.stdout.write("swift: CLI comparison passed\n");

  command("haxe", ["packages/driver/dart.hxml"]);
  outputs.push(compare("dart", ["run", "out/driver/dart/gen/lib/driver/main.dart"]));
  verifications.push(verify("dart", ["run", "out/driver/dart/gen/lib/driver/main.dart"]));
  rootFiles.push(roots("dart", ["run", "out/driver/dart/gen/lib/driver/main.dart"]));
  process.stdout.write("dart: CLI comparison passed\n");

  for (const output of outputs) {
    if (output !== outputs[0]) throw new Error(`CLI comparison differs by target:\n${outputs.join("\n---\n")}`);
  }
  for (const output of verifications) {
    if (output !== verifications[0]) throw new Error(`CLI verification differs by target:\n${verifications.join("\n---\n")}`);
  }
  for (const contents of rootFiles) {
    if (contents !== rootFiles[0]) throw new Error(`CLI roots differ by target:\n${rootFiles.join("\n---\n")}`);
  }
  process.stdout.write("The JS and five translated CLIs produced the same comparison, verification, and roots file.\n");
} finally {
  rmSync(fixture, { recursive: true, force: true });
}
