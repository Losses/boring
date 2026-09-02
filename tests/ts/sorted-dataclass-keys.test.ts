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
    expect(read("ts/gen/boring/PrintedEnumOps.ts")).toContain(`export function PrintedBadgemarkOrder(v: PrintedMark): number {
  if (v.kind === "Tag") return 2;
  if (v.kind === "Ring") return 1;
  if (v.kind === "Plain") return 0;
  return 0;
}`);
    expect(read("ts/gen/boring/PrintedEnumOps.ts")).toContain(`if (PrintedBadgemarkOrder(a.mark) !== PrintedBadgemarkOrder(b.mark)) return PrintedBadgemarkOrder(a.mark) - PrintedBadgemarkOrder(b.mark);`);
    expect(read("kotlin/gen/boring/PrintedEnumOps.kt")).toContain(`fun PrintedBadgemarkOrder(v: PrintedMark): Int = when (v) {
        is PrintedMark.Tag -> 2
        is PrintedMark.Ring -> 1
        PrintedMark.Plain -> 0
    }`);
    expect(read("dart/gen/lib/boring/printed_enum_ops.dart")).toContain(`int PrintedBadgemarkOrder(PrintedMark v) {
    if (v is PrintedMarkTag) return 2;
    if (v is PrintedMarkRing) return 1;
    if (v is PrintedMarkPlain) return 0;
    return 0;
  }`);
    expect(read("rust-gen/src/boring/printed_enum_ops.rs")).toContain(`fn printed_badge_mark_order(v: &PrintedMark) -> i32 {
    match v {
        PrintedMark::Tag { .. } => 2,
        PrintedMark::Ring { .. } => 1,
        PrintedMark::Plain => 0,
    }
}`);
  });
});
