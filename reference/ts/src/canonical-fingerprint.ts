import { createHash } from "node:crypto";

/**
 * One framed field of a P-23 protocol fingerprint. The value bytes are already
 * canonical for the declared type tag; floats come from FloatCanonical
 * (encode64/encode32), and null is signalled by the marker rather than bytes.
 */
export interface FingerprintField {
  readonly key: string;
  readonly typeTag: number;
  readonly isNull: boolean;
  readonly value: Uint8Array;
}

export const TAG_F64 = 1;
export const TAG_F32 = 2;
export const TAG_I64 = 3;
export const TAG_BOOL = 4;
export const TAG_STR = 5;

/**
 * P-23 protocol fingerprint: SHA-256 over a canonical byte framing. Every
 * field contributes, in declaration order: u16 key byte length (big-endian),
 * the key's UTF-8 bytes, a u8 type tag, a u8 null marker (0 present / 1 null),
 * then the canonical value bytes when present. SHA-256 is the fixed digest.
 */
export function encodeFingerprint(fields: readonly FingerprintField[]): Uint8Array {
  const chunks: number[] = [];
  for (const field of fields) {
    const keyBytes: number[] = [];
    for (let i = 0; i < field.key.length; i += 1) {
      keyBytes.push(field.key.charCodeAt(i) & 0xff);
    }
    chunks.push((keyBytes.length >>> 8) & 0xff, keyBytes.length & 0xff);
    chunks.push(...keyBytes);
    chunks.push(field.typeTag & 0xff);
    chunks.push(field.isNull ? 1 : 0);
    if (!field.isNull) {
      for (let i = 0; i < field.value.length; i += 1) {
        chunks.push(field.value[i]);
      }
    }
  }
  return new Uint8Array(createHash("sha256").update(new Uint8Array(chunks)).digest());
}
