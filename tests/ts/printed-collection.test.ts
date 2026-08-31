import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");
function read(file: string): string { return fs.readFileSync(path.join(root, file), "utf8"); }

describe("record collection printed members", () => {
  test("non-Kotlin targets route collection fields through single-pass builders", () => {
    const trees = [
      ["reference/ts/gen/boring/PrintedCollection.ts", "(() => { let out = \"[\"", "this.points[i]!.toString()"],
      ["reference/swift/gen/boring/PrintedCollection.swift", "{ () -> String in var out = \"[\"", "self.points[i].toString()"],
      ["reference/swift-f32/gen/boring/PrintedCollection.swift", "{ () -> String in var out = \"[\"", "self.points[i].toString()"],
      ["reference/dart/gen/lib/boring/printed_collection.dart", "StringBuffer(\"[\")", "sb.write(this.points[i].toString())"],
      ["reference/rust-gen/src/boring/printed_collection.rs", "String::new()", "self.points[i].to_string()"],
      ["reference/rust-f32-gen/src/boring/printed_collection.rs", "String::new()", "self.points[i].to_string()"],
    ];
    for (const [file, builder, nested] of trees) {
      const content = read(file);
      expect(content).toContain(builder);
      expect(content).toContain(nested);
      expect(content).not.toContain(".map(");
      expect(content).not.toContain("joinToString(");
      expect(content).not.toContain(".joined(");
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
