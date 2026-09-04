package tscompiler;

#if (macro || reflaxe_runtime)
/**
    Source of the runtime module emitted next to the generated files.
    It only hosts what the translatable subset cannot express inline:
    the Int64 bit representation (stdlib/05) and the growable byte
    sink behind haxe.io.BytesBuffer (stdlib/02).
**/
class TsRuntime {
    public static final SOURCE = '
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

export function readUnit(text: string, index: number): number | null {
  const c = text.charCodeAt(index);
  return Number.isNaN(c) ? null : c;
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

  add(bytes: Uint8Array): void {
    if(this.length + bytes.length > this.bytes.length) {
      let capacity = this.bytes.length;
      while(capacity < this.length + bytes.length) {
        capacity *= 2;
      }
      const grown = new Uint8Array(capacity);
      grown.set(this.bytes);
      this.bytes = grown;
    }
    this.bytes.set(bytes, this.length);
    this.length += bytes.length;
  }

  getBytes(): Uint8Array {
    return this.bytes.slice(0, this.length);
  }
}

';

    /**
        Source of the test entry emitted beside the runtime module. It
        holds the test result writer, the only runtime member that needs
        the host file system; the general entry above stays free of node
        imports so a browser can load it.
    **/
    public static final TEST_SOURCE = 'import * as fs from "node:fs";
import * as path from "node:path";

export type TestBody = () => void;

export function readUnit(text: string, index: number): number | null {
  const c = text.charCodeAt(index);
  return Number.isNaN(c) ? null : c;
}

export class Test {
  private static currentTestId: string | null = null;

  // Host edges of the test entry (P6): the runner state, the raise of
  // this language, the reflection-based formatting of aggregates, and
  // the result-file edge. Assertion checks and scalar formatting live
  // in TestCore, appended after this class in this same file.
  static currentTestIdState(): string {
    return Test.currentTestId ?? "";
  }

  static run(id: string, name: string, body: TestBody): void {
    Test.currentTestId = id;
    try {
      body();
      Test.recordResult(id, name, "pass", null);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      Test.recordResult(id, name, "fail", msg);
      throw err;
    } finally {
      Test.currentTestId = null;
    }
  }

  static ok(condition: boolean, message?: string | null): void {
    TestCore.ok(condition, message ?? "");
  }

  static equals<T>(expected: T, actual: T, message?: string | null): void {
    if (!Test.deepEquals(expected, actual)) {
      const canonical = TestCore.formatCanonicalMessage(
        Test.currentTestIdState(),
        message ?? "",
        Test.formatValue(expected),
        Test.formatValue(actual),
        true
      );
      throw new Error(canonical);
    }
  }

  static fail(message: string): void {
    TestCore.fail(message);
  }

  private static formatValue(v: unknown): string {
    if (v === null) return "null";
    if (typeof v === "boolean") return TestCore.formatBool(v);
    if (typeof v === "number") return TestCore.formatFloat(v);
    if (typeof v === "string") {
      return String.fromCharCode(34) + TestCore.escapeJson(v) + String.fromCharCode(34);
    }
    if (v instanceof Uint8Array) {
      return TestCore.formatBytes(v);
    }
    if (Array.isArray(v)) {
      let out = "[";
      for (let i = 0, len = v.length; i < len; i += 1) {
        if (i > 0) out += ", ";
        out += Test.formatValue(v[i]);
      }
      return out + "]";
    }
    if (typeof v === "object") {
      const obj = v as Record<string, unknown>;
      const keys = Object.keys(obj);
      if ("kind" in obj && typeof obj["kind"] === "string") {
        const kind = obj["kind"] as string;
        const payloadKeys: string[] = [];
        for (let i = 0, len = keys.length; i < len; i += 1) {
          const k = keys[i];
          if (k !== undefined && k !== "kind") payloadKeys.push(k);
        }
        if (payloadKeys.length === 0) {
          return kind;
        } else {
          let out = kind + "(";
          for (let i = 0, len = payloadKeys.length; i < len; i += 1) {
            if (i > 0) out += ", ";
            const pk = payloadKeys[i];
            out += Test.formatValue(pk !== undefined ? obj[pk] : undefined);
          }
          return out + ")";
        }
      }
      let out = "{";
      for (let i = 0, len = keys.length; i < len; i += 1) {
        if (i > 0) out += ", ";
        const k = keys[i];
        out += (k ?? "") + ": " + Test.formatValue(k !== undefined ? obj[k] : undefined);
      }
      return out + "}";
    }
    return String(v);
  }

  private static deepEquals(a: unknown, b: unknown): boolean {
    if (a === b) {
      if (typeof a === "number" && typeof b === "number") {
        if (Number.isNaN(a) || Number.isNaN(b)) return false;
      }
      return true;
    }
    if (typeof a === "number" && typeof b === "number") {
      if (Number.isNaN(a) || Number.isNaN(b)) return false;
      return a === b;
    }
    if (a === null || b === null || typeof a !== typeof b) return false;
    if (a instanceof Uint8Array && b instanceof Uint8Array) {
      if (a.length !== b.length) return false;
      for (let i = 0, len = a.length; i < len; i += 1) {
        if (a[i] !== b[i]) return false;
      }
      return true;
    }
    if (Array.isArray(a) && Array.isArray(b)) {
      if (a.length !== b.length) return false;
      for (let i = 0, len = a.length; i < len; i += 1) {
        if (!Test.deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (typeof a === "object" && typeof b === "object") {
      const oa = a as Record<string, unknown>;
      const ob = b as Record<string, unknown>;
      const ka = Object.keys(oa);
      const kb = Object.keys(ob);
      if (ka.length !== kb.length) return false;
      for (let i = 0, len = ka.length; i < len; i += 1) {
        const k = ka[i];
        if (k === undefined) continue;
        if (!Object.prototype.hasOwnProperty.call(ob, k)) return false;
        if (!Test.deepEquals(oa[k], ob[k])) return false;
      }
      return true;
    }
    return false;
  }

  private static recordResult(id: string, name: string, verdict: "pass" | "fail", message: string | null): void {
    const envPath = typeof process !== "undefined" && process.env ? process.env["BORING_TEST_RESULTS"] : null;
    const filePath = envPath && envPath.length > 0 ? envPath : "out/test-results/ts.jsonl";
    const jsonLine = TestCore.resultLine(id, name, verdict === "fail", message ?? "");
    try {
      const dir = path.dirname(filePath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.appendFileSync(filePath, jsonLine);
    } catch {
      // Ignore if filesystem is unavailable in sandbox
    }
  }
}
';
}
#end
