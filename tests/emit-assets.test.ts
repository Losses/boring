import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * Emit-Assets contract (t-mvlogmat-pam8): a @:asset data module's large
 * string literal is externalized to a data file plus a native resource read,
 * instead of inlining as a string literal. The same fixture must externalize
 * on all four non-Rust targets (TS, Kotlin, Swift, Dart).
 */

const root = path.resolve(import.meta.dir, "..");
const scratch =
  Bun.env.BORING_EMIT_ASSETS_OUT ??
  path.join(root, "out", "emit-assets", "test-" + randomUUID());

function observe(command: string[], cwd: string) {
  const result = Bun.spawnSync(command, { cwd, stdout: "pipe", stderr: "pipe" });
  return { code: result.exitCode, stdout: result.stdout.toString(), stderr: result.stderr.toString() };
}

function generate(hxml: string, defs: string[]) {
  return observe(["haxe", hxml, ...defs], root);
}

function read(p: string): string { return fs.readFileSync(p, "utf8"); }
function exists(p: string): boolean { return fs.existsSync(p); }

const FRAGMENT = "line-000-abcdefghijklmnopqrstuvwxyz";

test("emit-assets: @:asset module externalizes its payload on all four targets", async () => {
  fs.mkdirSync(scratch, { recursive: true });

  // --- TypeScript: fsAsset readFileSync helper + emitted .txt --------------
  const ts = path.join(scratch, "ts");
  const tsRun = generate("tests/haxe/emit-assets/gen/ts.hxml", [
    "-D", "ts-output=" + ts + "/gen",
    "-D", "ts-test-output=" + ts + "/gen-tests",
    "-D", "ts-test-runner=bun",
  ]);
  expect(tsRun.code, "ts generation failed: " + tsRun.stderr).toBe(0);
  expect(exists(ts + "/gen/probe/AssetData__asset_0.txt")).toBe(true);
  const tsMod = read(ts + "/gen/probe/AssetData.ts");
  expect(tsMod).toContain("fsAsset");
  expect(tsMod).toContain("AssetData__asset_0.txt");
  expect(tsMod).not.toContain(FRAGMENT);

  // --- Kotlin: getResourceAsStream + emitted .txt --------------------------
  const kt = path.join(scratch, "kt");
  const ktRun = generate("tests/haxe/emit-assets/gen/kotlin.hxml", [
    "-D", "kotlin-output=" + kt + "/gen",
    "-D", "kotlin-test-output=" + kt + "/gen-tests",
  ]);
  expect(ktRun.code, "kotlin generation failed: " + ktRun.stderr).toBe(0);
  expect(exists(kt + "/gen/probe/AssetData__asset_0.txt")).toBe(true);
  const ktMod = read(kt + "/gen/probe/AssetData.kt");
  expect(ktMod).toContain("getResourceAsStream");
  expect(ktMod).toContain("AssetData__asset_0.txt");
  expect(ktMod).not.toContain(FRAGMENT);

  // --- Swift: Bundle.main read + emitted .txt ------------------------------
  const sw = path.join(scratch, "sw");
  const swRun = generate("tests/haxe/emit-assets/gen/swift.hxml", [
    "-D", "swift-output=" + sw + "/gen",
    "-D", "swift-test-output=" + sw + "/gen-tests",
    "-D", "swift-test-runner=native",
    "-D", "swift-test-import=Codec",
  ]);
  expect(swRun.code, "swift generation failed: " + swRun.stderr).toBe(0);
  expect(exists(sw + "/gen/probe/AssetData__asset_0.txt")).toBe(true);
  const swMod = read(sw + "/gen/probe/AssetData.swift");
  expect(swMod).toContain("Bundle.main");
  expect(swMod).toContain("AssetData__asset_0");
  expect(swMod).not.toContain(FRAGMENT);

  // --- Dart: File.readAsStringSync + emitted .txt --------------------------
  const dart = path.join(scratch, "dart");
  const dartRun = generate("tests/haxe/emit-assets/gen/dart.hxml", [
    "-D", "dart-output=" + dart + "/gen",
    "-D", "dart-test-output=" + dart + "/gen-tests",
    "-D", "dart-test-runner=native",
  ]);
  expect(dartRun.code, "dart generation failed: " + dartRun.stderr).toBe(0);
  expect(exists(dart + "/gen/lib/probe/AssetData__asset_0.txt")).toBe(true);
  const dartMod = read(dart + "/gen/lib/probe/asset_data.dart");
  expect(dartMod).toContain("readAsStringSync");
  expect(dartMod).toContain("AssetData__asset_0.txt");
  expect(dartMod).not.toContain(FRAGMENT);

  // --- The emitted asset file itself is raw (contains the payload) ---------
  expect(read(ts + "/gen/probe/AssetData__asset_0.txt")).toContain(FRAGMENT);
}, 600_000);
