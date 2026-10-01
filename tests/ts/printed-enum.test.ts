import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");
const read = (f: string) => fs.readFileSync(path.join(root, f), "utf8");
describe("enum printed forms", () => {
  test("generated trees contain enum operands and badge member", () => {
    expect(read("reference/ts/gen/boring/PrintedEnumOps.ts")).toContain("kind");
    expect(read("reference/ts/gen/boring/PrintedEnumOps.ts")).toContain("PrintedBadge");
    for (const [target, f] of [
      ["swift", "reference/swift/gen/boring/PrintedEnumOps.swift"],
      ["dart", "reference/dart/gen/lib/boring/printed_enum_ops.dart"],
      ["rust", "reference/rust/gen/boring/printed_enum_ops.rs"],
    ] as const) {
      withTargetTree(target, "printed-enum: generated trees contain enum operands and badge member", () => {
        expect(read(f)).toContain("PrintedMark");
      });
    }
    expect(read("reference/kotlin/gen/boring/PrintedEnumOps.kt")).toContain("PrintedMark");
  });
  test("generated trees contain array enum constructors", () => {
    for (const [target, f] of [
      ["ts", "reference/ts/gen/boring/PrintedEnumOps.ts"],
      ["kotlin", "reference/kotlin/gen/boring/PrintedEnumOps.kt"],
      ["swift", "reference/swift/gen/boring/PrintedEnumOps.swift"],
      ["dart", "reference/dart/gen/lib/boring/printed_enum_ops.dart"],
      ["rust", "reference/rust/gen/boring/printed_enum_ops.rs"],
    ] as const) {
      withTargetTree(target, "printed-enum: generated trees contain array enum constructors", () => {
        const content = read(f);
        expect(content).toContain("Trail");
        expect(content).toContain("Aliases");
      });
    }
  });
});
