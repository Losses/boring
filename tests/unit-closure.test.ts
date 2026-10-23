import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * Emit-UnitClosure contract: a main data class with no @:test that only test
 * code references is reclassified to the tests unit, so a release build stops
 * shipping it while the test tree still carries it. The classification lives in
 * the shared CompilationUnits layer, so the same golden fixture must route the
 * same way on all five targets (criterion 3 of t-mvlgr030-v2c8).
 */

const root = path.resolve(import.meta.dir, "..");
const scratch =
  Bun.env.BORING_UNIT_CLOSURE_OUT ??
  path.join(root, "out", "unit-closure", "test-" + randomUUID());

function observe(command: string[], cwd: string) {
  const result = Bun.spawnSync(command, { cwd, stdout: "pipe", stderr: "pipe" });
  return {
    code: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

function generate(hxml: string, defs: string[], out: string) {
  return observe(["haxe", hxml, ...defs], root);
}

function exists(p: string): boolean {
  return fs.existsSync(p);
}

function read(p: string): string {
  return fs.readFileSync(p, "utf8");
}

function subdirs(base: string): string[] {
  if (!fs.existsSync(base)) return [];
  return fs.readdirSync(base);
}

test("unit-closure: test-only main data class leaves release on all five targets", async () => {
  fs.mkdirSync(scratch, { recursive: true });

  // --- Rust: cfg(test) marking ---------------------------------------------
  const rust = path.join(scratch, "rust");
  fs.mkdirSync(rust, { recursive: true });
  const rustDefs = [
    "-D", "rust-output=" + rust + "/gen",
    "-D", "rust-test-output=" + rust + "/gen-tests",
    "-D", "compilation_units_dump=" + rust + "/units.tsv",
  ];
  const rustRun = generate("tests/haxe/unit-closure/gen/rust.hxml", rustDefs, rust);
  expect(rustRun.code, "rust generation failed: " + rustRun.stderr).toBe(0);
  const rustUnits = read(rust + "/units.tsv");
  expect(rustUnits).toContain("probe.GoldenData\ttests");
  expect(rustUnits).toContain("probe.MainEntry\tmain");
  expect(read(rust + "/gen/probe/golden_data.rs").startsWith("#![cfg(test)]")).toBe(true);
  expect(read(rust + "/gen/probe/main_entry.rs").startsWith("#![cfg(test)]")).toBe(false);

  // --- TypeScript: separate test tree --------------------------------------
  const ts = path.join(scratch, "ts");
  fs.mkdirSync(ts, { recursive: true });
  const tsDefs = [
    "-D", "ts-output=" + ts + "/gen",
    "-D", "ts-test-output=" + ts + "/gen-tests",
    "-D", "ts-test-runner=bun",
  ];
  const tsRun = generate("tests/haxe/unit-closure/gen/ts.hxml", tsDefs, ts);
  expect(tsRun.code, "ts generation failed: " + tsRun.stderr).toBe(0);
  expect(exists(ts + "/gen/probe/GoldenData.ts")).toBe(false);
  expect(exists(ts + "/gen/probe/MainEntry.ts")).toBe(true);
  expect(exists(ts + "/gen-tests/probe/GoldenData.test.ts")).toBe(true);

  // --- Kotlin: separate test tree + shared dump ----------------------------
  const kt = path.join(scratch, "kt");
  fs.mkdirSync(kt, { recursive: true });
  const ktDefs = [
    "-D", "kotlin-output=" + kt + "/gen",
    "-D", "kotlin-test-output=" + kt + "/gen-tests",
    "-D", "compilation_units_dump=" + kt + "/units.tsv",
  ];
  const ktRun = generate("tests/haxe/unit-closure/gen/kotlin.hxml", ktDefs, kt);
  expect(ktRun.code, "kotlin generation failed: " + ktRun.stderr).toBe(0);
  const ktUnits = read(kt + "/units.tsv");
  expect(ktUnits).toContain("probe.GoldenData\ttests");
  expect(ktUnits).toContain("probe.MainEntry\tmain");
  expect(exists(kt + "/gen/probe/GoldenData.kt")).toBe(false);
  expect(exists(kt + "/gen/probe/MainEntry.kt")).toBe(true);
  expect(exists(kt + "/gen-tests/probe/GoldenData.kt")).toBe(true);

  // --- Swift: separate test tree + shared dump -----------------------------
  const sw = path.join(scratch, "sw");
  fs.mkdirSync(sw, { recursive: true });
  const swDefs = [
    "-D", "swift-output=" + sw + "/gen",
    "-D", "swift-test-output=" + sw + "/gen-tests",
    "-D", "swift-test-runner=native",
    "-D", "swift-test-import=Codec",
    "-D", "compilation_units_dump=" + sw + "/units.tsv",
  ];
  const swRun = generate("tests/haxe/unit-closure/gen/swift.hxml", swDefs, sw);
  expect(swRun.code, "swift generation failed: " + swRun.stderr).toBe(0);
  const swUnits = read(sw + "/units.tsv");
  expect(swUnits).toContain("probe.GoldenData\ttests");
  expect(swUnits).toContain("probe.MainEntry\tmain");
  expect(exists(sw + "/gen/probe/GoldenData.swift")).toBe(false);
  expect(exists(sw + "/gen/probe/MainEntry.swift")).toBe(true);
  expect(exists(sw + "/gen-tests/probe/GoldenData.swift")).toBe(true);

  // --- Dart: separate test tree --------------------------------------------
  const dart = path.join(scratch, "dart");
  fs.mkdirSync(dart, { recursive: true });
  const dartDefs = [
    "-D", "dart-output=" + dart + "/gen",
    "-D", "dart-test-output=" + dart + "/gen-tests",
    "-D", "dart-test-runner=native",
  ];
  const dartRun = generate("tests/haxe/unit-closure/gen/dart.hxml", dartDefs, dart);
  expect(dartRun.code, "dart generation failed: " + dartRun.stderr).toBe(0);
  expect(exists(dart + "/gen/lib/probe/golden_data.dart")).toBe(false);
  expect(exists(dart + "/gen/lib/probe/main_entry.dart")).toBe(true);
  expect(exists(dart + "/gen-tests/probe/golden_data.dart")).toBe(true);
}, 600_000);
