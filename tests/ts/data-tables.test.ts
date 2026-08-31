import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ScriptEvidenceTable } from "../../reference/ts/gen/boring/ScriptEvidenceTable.ts";
import { WordCharacterTable } from "../../reference/ts/gen/boring/WordCharacterTable.ts";
import { PayloadTextTable } from "../../reference/ts/gen/boring/PayloadTextTable.ts";
import { CodePointNames } from "../../reference/ts/gen/boring/CodePointNames.ts";

/**
 * Structural and behavioral assertions for compile-time data tables and sorted tables in TS,
 * per docs/specs/features/20-compile-time-data-tables.md and stdlib/07-sorted-keyed-tables.md.
 */

const GEN_DIR = join(import.meta.dir, "../../reference/ts/gen/boring");

describe("data tables TypeScript generation and behavior", () => {
  test("ScriptEvidenceTable emits new Int32Array table form without per-element unrolling", () => {
    const source = readFileSync(join(GEN_DIR, "ScriptEvidenceTable.ts"), "utf8");
    expect(source.includes("new Int32Array(")).toBe(true);
    expect(source.includes("const RANGES = new Int32Array([")).toBe(true);
    // Must not contain class-level static array property declaration
    expect(source.includes("static RANGES")).toBe(false);
  });

  test("WordCharacterTable emits new Int32Array table form without per-element unrolling", () => {
    const source = readFileSync(join(GEN_DIR, "WordCharacterTable.ts"), "utf8");
    expect(source.includes("new Int32Array(")).toBe(true);
    expect(source.includes("const RANGES = new Int32Array([")).toBe(true);
    expect(source.includes("static RANGES")).toBe(false);
  });

  test("PayloadTextTable emits new Int32Array table form without per-element unrolling", () => {
    const source = readFileSync(join(GEN_DIR, "PayloadTextTable.ts"), "utf8");
    expect(source.includes("new Int32Array(")).toBe(true);
    expect(source.includes("const TEXT_UNITS = new Int32Array([")).toBe(true);
    expect(source.includes("static TEXT_UNITS")).toBe(false);
  });

  test("ScriptEvidenceTable.classify operates correctly on generated tree", () => {
    expect(ScriptEvidenceTable.classify(0x0020)).toBe(1);
    expect(ScriptEvidenceTable.classify(0x007e)).toBe(1);
    expect(ScriptEvidenceTable.classify(0x007f)).toBe(0);
    expect(ScriptEvidenceTable.classify(0x02fa00)).toBe(23);
    expect(ScriptEvidenceTable.classify(0x02fa20)).toBe(0);
  });

  test("WordCharacterTable.contains operates correctly on generated tree", () => {
    expect(WordCharacterTable.contains(0x0030)).toBe(true);
    expect(WordCharacterTable.contains(0x0039)).toBe(true);
    expect(WordCharacterTable.contains(0x003a)).toBe(false);
    expect(WordCharacterTable.contains(0x020000)).toBe(true);
    expect(WordCharacterTable.contains(0x020020)).toBe(false);
  });

  test("PayloadTextTable operates correctly on generated tree", () => {
    expect(PayloadTextTable.unitCount()).toBe(186);
    expect(PayloadTextTable.unitAt(0)).toBe(0x73);
    expect(PayloadTextTable.unitAt(184)).toBe(0xe9);
    expect(PayloadTextTable.unitAt(185)).toBe(0x0a);
    expect(PayloadTextTable.text()).toBe(
      'synthetic payload for boring spec 20 raw payload tables\n' +
        'second line with "quotes" and \\ backslash\n' +
        "third line plain digits 0123456789\n" +
        "final line with latin small letter e with acute café\n",
    );
  });

  test("CodePointNames operates correctly on generated tree", () => {
    expect(CodePointNames.nameOf(0x0041)).toBe("LATIN CAPITAL LETTER A");
    expect(CodePointNames.nameOf(0x0020)).toBe("SPACE");
    expect(CodePointNames.nameOf(0x9999)).toBe(null);
    expect(CodePointNames.describeOrder()).toBe(
      "10=LINE FEED; 32=SPACE; 48=DIGIT ZERO; 65=LATIN CAPITAL LETTER A; 66=LATIN CAPITAL LETTER B",
    );
  });
});
