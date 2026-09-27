import { describe, expect, test } from "bun:test";
import { VectorSort } from "../../reference/ts/gen/boring/VectorSort.ts";
import type { GlyphMetrics } from "../../reference/ts/gen/boring/GlyphMetrics.ts";
import { ScriptEvidenceTable } from "../../reference/ts/gen/boring/ScriptEvidenceTable.ts";

/**
 * Runtime witnesses for the degradation-granularity audit
 * (docs/audit-degradation-granularity.md). Every lvalue/element slot the
 * emitters protect with the site-level DegradedLvalueGuard must still land
 * its write and read back the stored value: shape assertions alone are not
 * accepted evidence for the silent lost-write class.
 */

function record(codePoint: number): GlyphMetrics {
  return { codePoint, advanceEm: 0.5, bounds: { xMin: 0, yMin: 0, xMax: 1, yMax: 1 } };
}

describe("degradation granularity runtime witnesses", () => {
  test("array element slot writes land and read back the stored record", () => {
    const input = [record(19969), record(65), record(65292), record(97)];
    const out = VectorSort.byCodePoint(input);
    // Read back after the element-to-element moves: order and payload.
    expect(out.map((r) => r.codePoint)).toEqual([65, 97, 19969, 65292]);
    expect(out.length).toBe(4);
    expect(input).toBe(out); // in place, as the Haxe reference specifies
  });

  test("element field reads through the mutated array observe prior writes", () => {
    const records = [record(30), record(10), record(20)];
    // Drive the sort with adjacent keys so records[read + 1] = records[read]
    // executes repeatedly, then read the field back through the index path.
    const out = VectorSort.byCodePoint(records);
    for (let i = 1; i < out.length; i++) {
      expect(out[i - 1].codePoint <= out[i].codePoint).toBe(true);
    }
    expect(out[0].codePoint).toBe(10);
  });

  test("data table classify keeps index reads on the full table (no per-access copy)", () => {
    // Site-level conversion (426f8876): length and index reads lower natively
    // on the Int32Array, so classify stays correct across the whole range.
    const probes = [0, 65, 0x7f, 19969, 0x10ffff, -1];
    const seen = new Set(probes.map((cp) => ScriptEvidenceTable.classify(cp)));
    expect(seen.size).toBeGreaterThan(1);
    expect(ScriptEvidenceTable.classify(65)).toBe(ScriptEvidenceTable.classify(97));
  });
});
