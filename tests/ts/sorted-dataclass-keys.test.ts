import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("sorted dataClass key generated trees", () => {
  const read = (relative: string) => fs.readFileSync(path.resolve(__dirname, "../../reference", relative), "utf8");
  const comparator = (relative: string, name: string) => {
    const text = read(relative);
    const start = text.indexOf(name);
    expect(start).toBeGreaterThanOrEqual(0);
    const end = text.indexOf("\n}\n", start) + 3;
    return text.slice(start, end);
  };

  test("pins dataClass computed key properties", () => {
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain(`public get isEmpty(): boolean {
    return this.get_isEmpty();
  }`);
    expect(read("kotlin/gen/boring/SortedDataClassKeysOps.kt")).toContain(`val isEmpty: Boolean get() = get_isEmpty()`);
    expect(read("swift/gen/boring/SortedDataClassKeysOps.swift")).toContain(`var isEmpty: Bool { get_isEmpty() }`);
    expect(read("rust-gen/src/boring/sorted_data_class_keys_ops.rs")).toContain(`pub fn get_is_empty(&self) -> bool {
        return self.start == self.end;
    }`);
    expect(read("dart/gen/lib/boring/sorted_data_class_keys_ops.dart")).toContain(`bool get isEmpty => get_isEmpty();`);
  });

  test("pins nullable folded constructor defaults", () => {
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain("locale: string | null =");
    expect(read("kotlin/gen/boring/SortedDataClassKeysOps.kt")).toContain("locale: String? =");
    expect(read("swift/gen/boring/SortedDataClassKeysOps.swift")).toContain("_ locale: String?? = nil");
    expect(read("dart/gen/lib/boring/sorted_data_class_keys_ops.dart")).toContain("[String? locale]");
  });

  test("pins mutation evidence fixtures", () => {
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain("arrayMutations");
    expect(read("kotlin/gen/boring/SortedDataClassKeysOps.kt")).toContain("arrayMutations");
    expect(read("swift/gen/boring/SortedDataClassKeysOps.swift")).toContain("arrayMutations");
    expect(read("dart/gen/lib/boring/sorted_data_class_keys_ops.dart")).toContain("arrayMutations");
    expect(read("rust-gen/src/boring/sorted_data_class_keys_ops.rs")).toContain("array_mutations");
    for (const file of [
      "ts/gen/boring/SortedDataClassKeysOps.ts",
      "kotlin/gen/boring/SortedDataClassKeysOps.kt",
      "swift/gen/boring/SortedDataClassKeysOps.swift",
      "dart/gen/lib/boring/sorted_data_class_keys_ops.dart",
      "rust-gen/src/boring/sorted_data_class_keys_ops.rs",
    ]) {
      expect(read(file)).toContain(file.includes("rust") ? "nullable_mutation" : "nullableMutation");
    }
  });

  test("pins resident comparators", () => {
    const targets = [
      ["ts/gen/boring/SortedDataClassKeysOps.ts", "export function compareRubySpan"],
      ["kotlin/gen/boring/SortedDataClassKeysOps.kt", "fun compareRubySpan"],
      ["swift/gen/boring/SortedDataClassKeysOps.swift", "func compareRubySpan"],
      ["rust-gen/src/boring/sorted_data_class_keys_ops.rs", "pub fn compare_ruby_span"],
      ["dart/gen/lib/boring/sorted_data_class_keys_ops.dart", "int compareRubySpan"]
    ] as const;
    for (const [file, marker] of targets) {
      const body = comparator(file, marker);
      expect(body.toLowerCase().replaceAll("_", "")).toContain("fontfamilies");
      expect(body.toLowerCase()).toContain("kind");
      expect(body.toLowerCase()).toContain("locale");
    }
    expect(comparator("ts/gen/boring/SortedDataClassKeysOps.ts", "export function compareTextRange")).toContain("a.start");
    expect(comparator("kotlin/gen/boring/SortedDataClassKeysOps.kt", "fun compareTextRange")).toContain("a.start");
    expect(comparator("rust-gen/src/boring/sorted_data_class_keys_ops.rs", "pub fn compare_text_range")).toContain("cmp_start");
    expect(read("ts/gen/boring/PrintedEnumOps.ts")).toContain("PrintedBadgemarkOrder");
    expect(read("kotlin/gen/boring/PrintedEnumOps.kt")).toContain("PrintedBadgemarkOrder");
    expect(read("dart/gen/lib/boring/printed_enum_ops.dart")).toContain("PrintedBadgemarkOrder");
    expect(read("rust-gen/src/boring/printed_enum_ops.rs")).toContain("printed_badge_mark_order");
  });
});
