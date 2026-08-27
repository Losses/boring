import { describe, expect, test } from "bun:test";
import { decodeVector } from "@boring/codec";
import { VectorCodec } from "../../ts/gen/boring/VectorCodec.ts";
import { VectorException } from "../../ts/gen/boring/VectorException.ts";
import { VectorSort } from "../../ts/gen/boring/VectorSort.ts";

/**
 * Behavior guard for the reflaxe-generated tree (tools/reflaxe/ts), per
 * docs/specs/targets/07-reflaxe-typescript-target.md M2/M3. The generated
 * modules run against the same vectors as the hand-written tree:
 *
 *   1. decode matches the oracle field by field on the roundtrip fixture;
 *   2. encode reproduces the fixture bytes exactly (roundtrip stability);
 *   3. the reachable exception variants match the oracle;
 *   4. counts at or above 2^31 throw the CountOverflow variant before
 *      any record byte is read, per the count domain ruled in
 *      docs/specs/binary/01-wire-format.md;
 *   5. the decoded value is frozen per features/18.
 */

const FIXTURE = import.meta.dir + "/../vectors/roundtrip.bin";

type GeneratedRecord = ReturnType<typeof VectorCodec.decode>[number];
type Action = () => unknown;
interface KindHolder {
  readonly kind: string;
}
interface ErrorHolder {
  readonly error: KindHolder;
}
interface CodePointHolder {
  codePoint: number;
}

async function loadFixture(): Promise<Uint8Array> {
  return new Uint8Array(await Bun.file(FIXTURE).arrayBuffer());
}

function variantBytes(base: Uint8Array, kind: "bad-magic" | "truncated" | "trailing" | "huge-count" | "boundary-count"): Uint8Array {
  const copy = base.slice();
  if(kind === "bad-magic") {
    copy[0] = 0;
  } else if(kind === "truncated") {
    return copy.slice(0, copy.length - 20);
  } else if(kind === "trailing") {
    const extended = new Uint8Array(copy.length + 1);
    extended.set(copy);
    return extended;
  } else if(kind === "huge-count") {
    copy[4] = 0xff;
    copy[5] = 0xff;
    copy[6] = 0xff;
    copy[7] = 0xff;
  } else {
    copy[4] = 0x80;
    copy[5] = 0x00;
    copy[6] = 0x00;
    copy[7] = 0x00;
  }
  return copy;
}

function thrownKind(action: Action): string {
  try {
    action();
    return "no-throw";
  } catch(error) {
    expect(error).toBeInstanceOf(VectorException);
    return (error as VectorException).error.kind;
  }
}

describe("generated tree behavior", () => {
  test("decode matches the oracle field by field", async () => {
    const bytes = await loadFixture();
    const oracle = decodeVector(bytes);
    const generated = VectorCodec.decode(bytes);
    expect(generated.length).toBe(oracle.length);
    for(let i = 0; i < oracle.length; i += 1) {
      const a = oracle[i]!;
      const g = generated[i]!;
      expect(g.codePoint).toBe(a.codePoint);
      expect(g.advanceEm).toBe(a.advanceEm);
      expect(g.bounds.xMin).toBe(a.bounds.xMin);
      expect(g.bounds.yMin).toBe(a.bounds.yMin);
      expect(g.bounds.xMax).toBe(a.bounds.xMax);
      expect(g.bounds.yMax).toBe(a.bounds.yMax);
    }
  });

  test("encode reproduces the fixture bytes exactly", async () => {
    const bytes = await loadFixture();
    const encoded = VectorCodec.encode(VectorCodec.decode(bytes));
    expect(encoded.length).toBe(bytes.length);
    for(let i = 0; i < bytes.length; i += 1) {
      expect(encoded[i]).toBe(bytes[i]);
    }
  });

  test("reachable exception variants match the oracle", async () => {
    const bytes = await loadFixture();
    for(const kind of ["bad-magic", "truncated", "trailing"] as const) {
      const input = variantBytes(bytes, kind);
      const oracleKind = (() => {
        try {
          decodeVector(input);
          return "no-throw";
        } catch(error) {
          return (error as ErrorHolder).error.kind;
        }
      })();
      expect(thrownKind(() => VectorCodec.decode(input))).toBe(oracleKind);
    }
  });

  test("counts at or above 2^31 throw CountOverflow before any record byte is read", async () => {
    const bytes = await loadFixture();
    for(const kind of ["huge-count", "boundary-count"] as const) {
      const input = variantBytes(bytes, kind);
      try {
        VectorCodec.decode(input);
        expect.unreachable();
      } catch(error) {
        expect(error).toBeInstanceOf(VectorException);
        const exception = error as VectorException;
        // The generated reader holds the count in a signed Int32, so the
        // guard compares against the negative half; the hand-written tree
        // reads the count unsigned and compares against 0x7fffffff. Both
        // reject the same domain, ruled in docs/specs/binary/01-wire-format.md.
        expect(exception.error.kind).toBe("CountOverflow");
        expect(exception.name).toBe("VectorException");
        expect(exception.message).toBe(VectorException.describe(exception.error));
      }
    }
  });

  test("sort orders by code point and is idempotent", async () => {
    const records = VectorCodec.decode(await loadFixture()) as GeneratedRecord[];
    const permutation = [3, 1, 0, 2];
    const shuffled: GeneratedRecord[] = [];
    for(const index of permutation) {
      shuffled.push(records[index]!);
    }
    const sorted = VectorSort.byCodePoint(shuffled) as GeneratedRecord[];
    expect(sorted.length).toBe(records.length);
    for(let i = 1; i < sorted.length; i += 1) {
      expect(sorted[i]!.codePoint >= sorted[i - 1]!.codePoint).toBe(true);
    }
    const again = VectorSort.byCodePoint(sorted) as GeneratedRecord[];
    for(let i = 0; i < sorted.length; i += 1) {
      expect(again[i]!.codePoint).toBe(sorted[i]!.codePoint);
    }
  });

  test("decoded records and their array are frozen", async () => {
    const decoded = VectorCodec.decode(await loadFixture());
    expect(Object.isFrozen(decoded)).toBe(true);
    expect(Object.isFrozen(decoded[0])).toBe(true);
    expect(Object.isFrozen(decoded[0]!.bounds)).toBe(true);
  });

  test("slot assignment through a mutable view throws TypeError", async () => {
    const mutableView = VectorCodec.decode(await loadFixture()) as GeneratedRecord[];
    expect(() => {
      mutableView[0] = mutableView[0]!;
    }).toThrow(TypeError);
  });

  test("array growth through a mutable view throws TypeError", async () => {
    const mutableView = VectorCodec.decode(await loadFixture()) as GeneratedRecord[];
    expect(() => {
      mutableView.push(mutableView[0]!);
    }).toThrow(TypeError);
  });

  test("record field assignment through a mutable view throws TypeError", async () => {
    const first = VectorCodec.decode(await loadFixture())[0] as CodePointHolder;
    expect(() => {
      first.codePoint = 66;
    }).toThrow(TypeError);
  });
});
