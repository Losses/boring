import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");
function read(file: string): string { return fs.readFileSync(path.join(root, file), "utf8"); }

describe("record collection printed members", () => {
  test("non-Kotlin targets route collection fields through single-pass builders", () => {
    // What this test is about is the BUILDER -- one pass, no functional
    // iteration -- which the three `not.toContain` checks below carry. The
    // per-target strings name the builder opening and the element read.
    //
    // The two Rust entries name the HOISTED form deliberately. The Rust emitter
    // (RustExpr.hx:10046) binds the receiver once and reads `arr[i]` rather than
    // repeating the clone at the index expression. An earlier revision pinned
    // `(self.points).clone()[i]`, the pre-hoist text; it stayed red until the
    // reference tree was regenerated and the emitter's current shape became
    // visible. The hoisted binding is the stronger assertion: it also shows the
    // receiver is cloned once rather than per element.
    const trees = [
      ["ts", "reference/ts/gen/boring/PrintedCollection.ts", "(() => { let out = \"[\"", "this.points[i]!.toString()"],
      ["swift", "reference/swift/gen/boring/PrintedCollection.swift", "{ () -> String in var out = \"[\"", "self.points[i].toString()"],
      ["swift-f32", "reference/swift-f32/gen/boring/PrintedCollection.swift", "{ () -> String in var out = \"[\"", "self.points[i].toString()"],
      ["dart", "reference/dart/gen/lib/boring/printed_collection.dart", "StringBuffer(\"[\")", "sb.write(this.points[i].toString())"],
      ["rust", "reference/rust/gen/boring/printed_collection.rs", "String::new()", "let arr = (self.points).clone();"],
      ["rust-f32", "reference/rust-f32/gen/boring/printed_collection.rs", "String::new()", "let arr = (self.points).clone();"],
    ] as const;
    for (const [target, file, builder, element] of trees) {
      withTargetTree(target, "printed-collection: non-Kotlin targets route collection fields through single-pass builders", () => {
        const content = read(file);
        expect(content).toContain(builder);
        expect(content).toContain(element);
        expect(content).not.toContain(".map(");
        expect(content).not.toContain("joinToString(");
        expect(content).not.toContain(".joined(");
      });
    }
  });

  test("the Rust builder reads the hoisted receiver instead of recloning per element", () => {
    for (const file of [
      "reference/rust/gen/boring/printed_collection.rs",
      "reference/rust-f32/gen/boring/printed_collection.rs",
    ]) {
      const content = read(file);
      // The point of the hoist: one clone, then indexed reads. A regression that
      // recloned inside the loop would satisfy the builder check above and fail
      // here.
      expect(content).toContain("let arr = (self.points).clone();");
      expect(content).toContain("arr[i].to_string()");
      expect(content).not.toContain("(self.points).clone()[i]");
    }
  });

  test("Kotlin relies on native data-class text", () => {
    for (const file of ["reference/kotlin/gen/boring/PrintedCollection.kt", "reference/kotlin-f32/gen/boring/PrintedCollection.kt"]) {
      const content = read(file);
      const start = content.indexOf("data class PrintedCollection");
      const end = content.indexOf("data class PrintedPoint");
      expect(start).toBeGreaterThanOrEqual(0);
      expect(content.slice(start, end)).not.toContain("toString");
    }
  });
});
