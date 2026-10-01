import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");
const read = (file: string) => fs.readFileSync(path.join(root, file), "utf8");

const trees = [
  ["ts", "reference/ts/gen/boring/PrintedSortedFields.ts"],
  ["swift", "reference/swift/gen/boring/PrintedSortedFields.swift"],
  ["rust", "reference/rust/gen/boring/printed_sorted_fields.rs"],
  ["dart", "reference/dart/gen/lib/boring/printed_sorted_fields.dart"],
] as const;

const forbidden = /\.map\(|\bjoin(?:ToString)?\(|\.joined\(|(?:marks|points|lookup|emptySet|emptyMap)\s*\.\s*toString\(\)/;

describe("printed sorted field trees", () => {
  test("all native targets retain resident collection members", () => {
    for (const [target, file] of trees) {
      withTargetTree(target, "printed-sorted-fields: all native targets retain resident collection members", () => {
        const source = read(file);
        expect(source).toContain("marks");
        expect(source).toContain("points");
        expect(source).toContain("lookup");
        expect(source).toMatch(/(?:\.at\(|\.key_at\(|\.keyAt\(|\.value_at\(|\.valueAt\(|\[i\]|\[index\]|\[i\d+\])/);
        expect(source).not.toMatch(forbidden);
      });
    }
  });

  test("Kotlin keeps data-class synthesis without resident members", () => {
    const source = read("reference/kotlin/gen/boring/PrintedSortedFields.kt");
    expect(source).toContain("data class PrintedSortedFields");
    expect(source).not.toContain("fun toString");
    expect(source).not.toContain("fun marksAt");
    expect(source).not.toContain("fun lookupKeyAt");
    expect(source).not.toMatch(forbidden);
  });
});
