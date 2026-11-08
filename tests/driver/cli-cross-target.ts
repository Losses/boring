// CLI cross-target driver probe — orchestration and assertions.
//
// Boundary (packages/test/README.md): the fixture project and stub toolchain
// construction live in packages/test/fixtures/cli-driver-fixture.ts, the
// command executor in packages/test/bin/cli-command.ts. This file keeps the
// per-backend orchestration and every pass/fail decision.
import { readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

import { command } from "../../packages/test/bin/cli-command.ts";
import { createCliFixture, type CliFixture } from "../../packages/test/fixtures/cli-driver-fixture.ts";

const root = resolve(".");
const fx: CliFixture = createCliFixture();
const { fixture, project, verifyRoot, afterGenLog, fakeToolsEnv } = fx;

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
