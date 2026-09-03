import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("sorted dataClass key generated trees", () => {
  test("pins dataClass computed key properties", () => {
    const read = (relative: string) => fs.readFileSync(path.resolve(__dirname, "../../reference", relative), "utf8");
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain(`public get isEmpty(): boolean {
    return this.get_isEmpty();
  }`);
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain(`export function compareRubySpan(a: RubySpan, b: RubySpan): number {
  if (a === b) return 0;
  { const cmp = compareTextRange(a.baseRange, b.baseRange); if (cmp !== 0) return cmp; }
  if (a.text !== b.text) return a.text < b.text ? -1 : 1;
  return 0;
}`);
    expect(read("kotlin/gen/boring/SortedDataClassKeysOps.kt")).toContain(`val isEmpty: Boolean get() = get_isEmpty()`);
    expect(read("kotlin/gen/boring/SortedDataClassKeysOps.kt")).toContain(`cmp = a.start.compareTo(b.start)
    if (cmp != 0) return cmp
    cmp = a.end.compareTo(b.end)
    if (cmp != 0) return cmp
    return 0`);
    expect(read("swift/gen/boring/SortedDataClassKeysOps.swift")).toContain(`var isEmpty: Bool { get_isEmpty() }`);
    expect(read("swift/gen/boring/SortedDataClassKeysOps.swift")).toContain(`if a.start != b.start { return a.start - b.start }
    if a.end != b.end { return a.end - b.end }
    return 0`);
    expect(read("rust-gen/src/boring/sorted_data_class_keys_ops.rs")).toContain(`pub fn get_is_empty(&self) -> bool {
        return self.start == self.end;
    }`);
    expect(read("rust-gen/src/boring/sorted_data_class_keys_ops.rs")).toContain(`let cmp_start = a.start.cmp(&b.start) as i32;
    if cmp_start != 0 { return cmp_start; }
    let cmp_end = a.end.cmp(&b.end) as i32;
    if cmp_end != 0 { return cmp_end; }
    0`);
    expect(read("dart/gen/lib/boring/sorted_data_class_keys_ops.dart")).toContain(`bool get isEmpty => get_isEmpty();`);
    expect(read("dart/gen/lib/boring/sorted_data_class_keys_ops.dart")).toContain(`if (a.start != b.start) return a.start - b.start;
  if (a.end != b.end) return a.end - b.end;
  return 0;`);
  });

  test("pins resident comparators", () => {
    const read = (relative: string) => fs.readFileSync(path.resolve(__dirname, "../../reference", relative), "utf8");
    expect(read("ts/gen/boring/SortedDataClassKeysOps.ts")).toContain(`export function compareRubySpan(a: RubySpan, b: RubySpan): number {
  if (a === b) return 0;
  { const cmp = compareTextRange(a.baseRange, b.baseRange); if (cmp !== 0) return cmp; }
  if (a.text !== b.text) return a.text < b.text ? -1 : 1;
  return 0;
}`);
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
