const DOUBLE_SCRATCH = new DataView(new ArrayBuffer(8));

export interface Int64Halves {
  readonly high: number;
  readonly low: number;
}

export function doubleToI64(value: number): Int64Halves {
  DOUBLE_SCRATCH.setFloat64(0, value);
  return { high: DOUBLE_SCRATCH.getUint32(0), low: DOUBLE_SCRATCH.getUint32(4) };
}

export function i64ToDouble(low: number, high: number): number {
  DOUBLE_SCRATCH.setUint32(0, high);
  DOUBLE_SCRATCH.setUint32(4, low);
  return DOUBLE_SCRATCH.getFloat64(0);
}

export class BytesBuffer {
  private bytes: Uint8Array;
  private length: number;

  constructor() {
    this.bytes = new Uint8Array(64);
    this.length = 0;
  }

  addByte(byte: number): void {
    if(this.length === this.bytes.length) {
      const grown = new Uint8Array(this.bytes.length * 2);
      grown.set(this.bytes);
      this.bytes = grown;
    }
    this.bytes[this.length] = byte;
    this.length += 1;
  }

  getBytes(): Uint8Array {
    return this.bytes.slice(0, this.length);
  }
}
