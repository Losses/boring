/**
 * Sequential big-endian binary codec. The writer and the reader are kept
 * symmetric by construction: both go through the same scratch DataView for
 * f64 values, so a round trip is byte-stable on every platform bun runs on.
 */

import { f16ToF32Bits, f32ToF16Bits } from "./fp16.ts";
import { VectorException } from "./vector-error.ts";

const SCRATCH_LENGTH = 8;

/** Growable big-endian writer over a byte buffer. */
export class BinaryWriter {
  private buffer: Uint8Array;
  private length: number;
  private readonly scratch: DataView;

  constructor() {
    this.buffer = new Uint8Array(64);
    this.length = 0;
    this.scratch = new DataView(new ArrayBuffer(SCRATCH_LENGTH));
  }

  writeU16(value: number): void {
    this.ensure(2);
    this.buffer[this.length] = (value >>> 8) & 0xff;
    this.buffer[this.length + 1] = value & 0xff;
    this.length += 2;
  }

  writeU32(value: number): void {
    this.ensure(4);
    this.buffer[this.length] = (value >>> 24) & 0xff;
    this.buffer[this.length + 1] = (value >>> 16) & 0xff;
    this.buffer[this.length + 2] = (value >>> 8) & 0xff;
    this.buffer[this.length + 3] = value & 0xff;
    this.length += 4;
  }

  writeF64(value: number): void {
    this.scratch.setFloat64(0, value, false);
    this.ensure(SCRATCH_LENGTH);
    for (let i = 0; i < SCRATCH_LENGTH; i += 1) {
      this.buffer[this.length + i] = this.scratch.getUint8(i);
    }
    this.length += SCRATCH_LENGTH;
  }

  writeF32(value: number): void {
    this.scratch.setFloat32(0, value, false);
    this.ensure(4);
    for (let i = 0; i < 4; i += 1) {
      this.buffer[this.length + i] = this.scratch.getUint8(i);
    }
    this.length += 4;
  }

  writeF16(value: number): void {
    this.scratch.setFloat32(0, value, false);
    this.writeU16(f32ToF16Bits(this.scratch.getUint32(0, false)));
  }

  writeAscii(value: string): void {
    const count = value.length;
    this.ensure(count);
    for (let i = 0; i < count; i += 1) {
      this.buffer[this.length + i] = value.charCodeAt(i) & 0xff;
    }
    this.length += count;
  }

  finish(): Uint8Array {
    return this.buffer.slice(0, this.length);
  }

  currentLength(): number {
    return this.length;
  }

  private ensure(extra: number): void {
    const required = this.length + extra;
    if (required <= this.buffer.length) return;
    let capacity = this.buffer.length;
    while (capacity < required) capacity *= 2;
    const grown = new Uint8Array(capacity);
    grown.set(this.buffer, 0);
    this.buffer = grown;
  }
}

/** Cursor-based big-endian reader over an immutable byte buffer. */
export class BinaryReader {
  private readonly view: DataView;
  private readonly scratch: DataView;
  private offset: number;

  constructor(bytes: Uint8Array) {
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.scratch = new DataView(new ArrayBuffer(4));
    this.offset = 0;
  }

  readU16(): number {
    this.ensureRemaining(2);
    const value = this.view.getUint16(this.offset, false);
    this.offset += 2;
    return value;
  }

  readU32(): number {
    this.ensureRemaining(4);
    const value = this.view.getUint32(this.offset, false);
    this.offset += 4;
    return value;
  }

  readF64(): number {
    this.ensureRemaining(SCRATCH_LENGTH);
    const value = this.view.getFloat64(this.offset, false);
    this.offset += 8;
    return value;
  }

  readF32(): number {
    this.ensureRemaining(4);
    const value = this.view.getFloat32(this.offset, false);
    this.offset += 4;
    return value;
  }

  readF16(): number {
    this.ensureRemaining(2);
    const bits = f16ToF32Bits(this.view.getUint16(this.offset, false));
    this.offset += 2;
    this.scratch.setUint32(0, bits, false);
    return this.scratch.getFloat32(0, false);
  }

  readAscii(length: number): string {
    this.ensureRemaining(length);
    let value = "";
    for (let i = 0; i < length; i += 1) {
      value += String.fromCharCode(this.view.getUint8(this.offset + i));
    }
    this.offset += length;
    return value;
  }

  remaining(): number {
    return this.view.byteLength - this.offset;
  }

  consumed(): number {
    return this.offset;
  }

  /**
   * Runs before every read, mirroring ensureRemaining in the Haxe, Rust, and
   * Kotlin readers: a short buffer reports the UnexpectedEof domain variant
   * instead of the DataView RangeError.
   */
  private ensureRemaining(length: number): void {
    if (this.view.byteLength - this.offset < length) {
      throw new VectorException({ kind: "UnexpectedEof" });
    }
  }
}
