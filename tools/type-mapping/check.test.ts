import { describe, expect, test } from "bun:test";
import { checkAll, checkIntRow, rowCells } from "./check.ts";

const fixtures = {
  mapping: [
    "| Haxe type | Rust type | TypeScript type | Kotlin type |",
    "| --- | --- | --- | --- |",
    "| `Int` | `u32` (`i32` inside resident runtime modules) | `number` | `Int` (`Long` when the declared range exceeds `0x7FFFFFFF`) |",
  ].join("\n"),
  numeric: [
    "Code points are represented as `Int` in Haxe, `u32` in Rust, `number` in TypeScript, and `Int` in Kotlin.",
    "`WireU32Be` maps to `Int`, `u32`, `number`, and `Int` for the wire.",
    "Haxe `Int` maps to `Int32`; Haxe `Float` maps to `Double`.",
  ].join("\n"),
  sortedTables: "the call boundary converts between the resident `i32` domain and the business unsigned domain.",
  unicodeAccess: "The resident class renders\n  haxe Int as i32 with byte cursors, while business modules render u32,",
  graphemes: "resident modules render\n  haxe Int as i32 because the clamping contracts carry negative values,\n  while business modules render u32.",
};

describe("rowCells", () => {
  test("splits a table row into trimmed cells without the pipes", () => {
    expect(rowCells("| `Int` | `u32` | `number` | `Int` |")).toEqual(["`Int`", "`u32`", "`number`", "`Int`"]);
  });
});

describe("checkIntRow", () => {
  test("accepts the current ruling row", () => {
    expect(() => checkIntRow(fixtures.mapping)).not.toThrow();
  });
  test("rejects a single-domain Rust cell", () => {
    const doctored = fixtures.mapping.replace("`u32` (`i32` inside resident runtime modules)", "`i32`");
    expect(() => checkIntRow(doctored)).toThrow(/Rust cell/);
  });
});

describe("checkAll", () => {
  test("accepts the aligned fragments", () => {
    expect(() => checkAll(fixtures)).not.toThrow();
  });
  test("rejects a stdlib dropping the resident domain", () => {
    expect(() => checkAll({ ...fixtures, sortedTables: "the boundary converts domains." })).toThrow(/stdlib\/07/);
  });
  test("rejects a stdlib dropping the cursor domain statement", () => {
    const doctored = fixtures.unicodeAccess.replace("haxe Int as i32 with byte cursors", "haxe Int as u32 with byte cursors");
    expect(() => checkAll({ ...fixtures, unicodeAccess: doctored })).toThrow(/stdlib\/10/);
  });
  test("rejects a features/07 wire row disagreeing with the mapping", () => {
    const doctored = fixtures.numeric.replace("`WireU32Be` maps to `Int`, `u32`, `number`, and `Int`", "`WireU32Be` maps to `Int`, `i32`, `number`, and `Int`");
    expect(() => checkAll({ ...fixtures, numeric: doctored })).toThrow(/features\/07/);
  });
});
