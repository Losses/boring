import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("sorted dataClass key generated trees", () => {
  test("pins resident comparators", () => {
    const read = (relative: string) => fs.readFileSync(path.resolve(__dirname, "../../reference", relative), "utf8");
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain(`export function compareTextRange(a: TextRange, b: TextRange): number {
  if (a === b) return 0;
  if (a.start !== b.start) return a.start - b.start;
  if (a.end !== b.end) return a.end - b.end;
  return 0;
}`);
    expect(read("kotlin/gen/boring/SortedDataClassKeysOps.kt")).toContain(`fun compareTextRange(a: TextRange, b: TextRange): Int {
    var cmp = 0
    cmp = a.start.compareTo(b.start)
    if (cmp != 0) return cmp
    cmp = a.end.compareTo(b.end)
    if (cmp != 0) return cmp
    return 0
}`);
    expect(read("rust-gen/src/boring/sorted_data_class_keys_ops.rs")).toContain(`pub fn compare_text_range(a: &TextRange, b: &TextRange) -> i32 {
    let cmp_start = a.start.cmp(&b.start) as i32;
    if cmp_start != 0 { return cmp_start; }
    let cmp_end = a.end.cmp(&b.end) as i32;
    if cmp_end != 0 { return cmp_end; }
    0
}`);
    for (const relative of ["ts/gen/boring/SortedDataClassKeysOps.ts", "kotlin/gen/boring/SortedDataClassKeysOps.kt", "rust-gen/src/boring/sorted_data_class_keys_ops.rs"]) expect(read(relative)).toMatch(/quoteType|quote_type/);
  });
});
