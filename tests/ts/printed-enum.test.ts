import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
const root = path.resolve(__dirname, "../..");
const read = (f: string) => fs.readFileSync(path.join(root, f), "utf8");
describe("enum printed forms", () => {
  test("generated trees contain enum operands and badge member", () => {
    expect(read("reference/ts/gen/boring/PrintedEnumOps.ts")).toContain("kind");
    expect(read("reference/ts/gen/boring/PrintedEnumOps.ts")).toContain("PrintedBadge");
    for (const f of ["reference/swift/gen/boring/PrintedEnumOps.swift", "reference/dart/gen/lib/boring/printed_enum_ops.dart", "reference/rust-gen/src/boring/printed_enum_ops.rs"]) expect(read(f)).toContain("PrintedMark");
    expect(read("reference/kotlin/gen/boring/PrintedEnumOps.kt")).toContain("PrintedMark");
  });
});
