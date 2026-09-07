import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

describe("enum sorted key generated trees", () => {
  const read = (relative: string) => fs.readFileSync(path.resolve(__dirname, "../../reference", relative), "utf8");

  test("pins parameterless enum comparator definitions", () => {
    expect(read("ts/gen/boring/EnumSortedKeysOps.ts")).toContain(`export function compareEnumTier(a: EnumTier, b: EnumTier): number {
  if (a === b) return 0;
  if (a.kind === "Low") return 0 - (b.kind === "Low" ? 0 : 0);
  if (a.kind === "Mid") return 1 - (b.kind === "Mid" ? 1 : 0);
  if (a.kind === "High") return 2 - (b.kind === "High" ? 2 : 0);
  return 0;
}`);
    expect(read("kotlin/gen/boring/EnumSortedKeysOps.kt")).toContain("fun compareEnumTier(a: EnumTier, b: EnumTier): Int = a.ordinal - b.ordinal");
    expect(read("swift/gen/boring/EnumSortedKeysOps.swift")).toContain(`public func compareEnumTier(_ a: EnumTier, _ b: EnumTier) -> Int32 {
    if a == b { return 0; }
    func rank(_ v: EnumTier) -> Int32 {
        switch v {
        case .low: return 0
        case .mid: return 1
        case .high: return 2
        }
    }
    return rank(a) - rank(b)
}`);
    expect(read("dart/gen/lib/boring/enum_sorted_keys_ops.dart")).toContain("int compareEnumTier(EnumTier a, EnumTier b) => a.index.compareTo(b.index);");
    expect(read("rust-gen/src/boring/enum_sorted_keys_ops.rs")).toContain(`pub fn compare_enum_tier(a: &EnumTier, b: &EnumTier) -> i32 {
    if a == b { return 0; }
    fn rank(v: &EnumTier) -> i32 {
        match v {
            EnumTier::Low => 0,
            EnumTier::Mid => 1,
            EnumTier::High => 2,
        }
    }
    rank(a) - rank(b)
}`);
  });

  test("pins qualified Dart comparator references", () => {
    expect(read("dart/gen-tests/tests/printed_collection_tests.dart")).toContain("printed_collection.comparePrintedNullableCollection");
    expect(read("dart/gen-tests/tests/enum_sorted_keys_tests.dart")).toContain("enum_sorted_keys_ops.describe()");
  });
});

/**
 * The pipeline only lowers classes whose source root is registered with
 * Intercept.run, so a bare `-cp tmp` class never reaches the sorted-key
 * classification. The isolated probe hxml follows the precedent in
 * tests/ts/constructed-state.test.ts. The sample avoids trace(): the
 * trace macro pulls the real standard library onto the std-shadow Bytes
 * shadow and aborts the compile before generation.
 */
test("payload enums are rejected as sorted keys", async () => {
  const root = path.resolve(__dirname, "../..");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "enumkeys-negative-"));
  const sourceRoot = path.join(dir, "src");
  try {
    fs.mkdirSync(path.join(sourceRoot, "boring"), { recursive: true });
    fs.writeFileSync(path.join(sourceRoot, "boring", "NegativePayloadKeys.hx"), [
      "package boring;",
      "import std.SortedSet;",
      "enum PayloadTier { Heavy(weight:Int); }",
      "class NegativePayloadKeys {",
      "    public static function describe():Int {",
      "        final b:SortedSetBuilder<PayloadTier> = SortedSet.builder();",
      "        b.put(Heavy(1));",
      "        return b.build().size();",
      "    }",
      "}",
    ].join("\n"));
    const hxml = path.join(dir, "probe.hxml");
    fs.writeFileSync(hxml, [
      "-lib reflaxe", "-lib boring",
      `-cp ${path.join(root, "packages/compiler/reflaxe/ts/std-shadow")}`,
      `-cp ${path.join(root, "packages/compiler/reflaxe/ts")}`,
      `-cp ${path.join(root, "samples")}`, `-cp ${sourceRoot}`,
      `--macro Intercept.run(["${sourceRoot}"])`,
      "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
      "--macro tscompiler.Compiler.use()", `-D ts-output=${path.join(dir, "out")}`,
      "-D", "runtime-import=@boring/runtime", `-D runtime-emit=${path.join(dir, "out")}`,
      "-D", "package-shell=none",
      "boring.NegativePayloadKeys", "",
    ].join("\n"));
    const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect(exitCode).not.toBe(0);
    expect(stderr).toContain("enums with payloads are not keys");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
