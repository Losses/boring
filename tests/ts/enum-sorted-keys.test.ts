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

test("payload enums are rejected as sorted keys", async () => {
  const repoRoot = path.resolve(__dirname, "../..");
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "enumkeys-negative-"));
  fs.mkdirSync(path.join(tmp, "boring"));
  fs.writeFileSync(path.join(tmp, "boring", "NegativePayloadKeys.hx"), [
    "package boring;",
    "import std.SortedSet;",
    "enum PayloadTier { Heavy(weight:Int); }",
    "class NegativePayloadKeys {",
    "    static final bad:SortedSetBuilder<PayloadTier> = SortedSet.builder();",
    "    static final used:Void = bad.put(Heavy(1));",
    "    public static function main():Void {}",
    "}",
  ].join("\n"));
  const proc = Bun.spawn(["haxe", "examples/ts.hxml", "-cp", tmp, "-main", "boring.NegativePayloadKeys", "--macro", "haxe.macro.Compiler.keep('boring.NegativePayloadKeys')"], {
    cwd: repoRoot,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
  fs.rmSync(tmp, { recursive: true, force: true });
  expect(exitCode).not.toBe(0);
  expect(stderr).toContain("enums with payloads are not keys");
});
