import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("sorted dataClass key generated trees", () => {
  test("each target emits the dataClass comparator and binds it at the table", () => {
    const roots = ["ts/gen/boring/SortedDataClassKeysOps.ts", "kotlin/gen/boring/SortedDataClassKeysOps.kt", "rust-gen/src/boring/sorted_data_class_keys_ops.rs", "dart/gen/lib/boring/sorted_data_class_keys_ops.dart", "swift/gen/boring/SortedDataClassKeysOps.swift"];
    for (const relative of roots) {
      const file = path.resolve(__dirname, "../../reference", relative);
      expect(fs.existsSync(file)).toBe(true);
      const source = fs.readFileSync(file, "utf8");
      expect(source).toContain("TextRange");
      expect(source).toMatch(/compare(TextRange|_text_range)/);
      expect(source).toMatch(/Sorted(Map|Table)|sorted/);
    }
  });
});
