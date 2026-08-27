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
import * as fs from "node:fs";
import * as path from "node:path";

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

export type TestBody = () => void;

export class Test {
  private static currentTestId: string | null = null;

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
    if (!condition) {
      const canonical = Test.formatCanonicalMessage(Test.currentTestId ?? "", message, null, null, false);
      throw new Error(canonical);
    }
  }

  static equals<T>(expected: T, actual: T, message?: string | null): void {
    if (!Test.deepEquals(expected, actual)) {
      const canonical = Test.formatCanonicalMessage(
        Test.currentTestId ?? "",
        message,
        Test.formatValue(expected),
        Test.formatValue(actual),
        true
      );
      throw new Error(canonical);
    }
  }

  static fail(message: string): void {
    const canonical = Test.formatCanonicalMessage(Test.currentTestId ?? "", message, null, null, false);
    throw new Error(canonical);
  }

  private static escapeJson(s: string): string {
    let out = "";
    for (let i = 0, len = s.length; i < len; i += 1) {
      const c = s.charAt(i);
      const code = s.charCodeAt(i);
      if (code === 0x22) out += String.fromCharCode(92, 34);
      else if (code === 0x5C) out += String.fromCharCode(92, 92);
      else if (code === 0x0A) out += String.fromCharCode(92, 110);
      else if (code === 0x0D) out += String.fromCharCode(92, 114);
      else if (code === 0x09) out += String.fromCharCode(92, 116);
      else if (code < 0x20) {
        out += String.fromCharCode(92, 117) + code.toString(16).padStart(4, "0");
      } else {
        out += c;
      }
    }
    return out;
  }

  private static formatCanonicalMessage(
    id: string,
    message: string | null | undefined,
    expectedStr: string | null,
    actualStr: string | null,
    isEquals: boolean
  ): string {
    const lines: string[] = ["test failed: " + id];
    if (message != null && message.length > 0) {
      lines.push("  message: " + message);
    }
    if (isEquals) {
      lines.push("  expected: " + (expectedStr ?? ""));
      lines.push("  actual:   " + (actualStr ?? ""));
    }
    return lines.join(String.fromCharCode(10));
  }

  private static formatValue(v: unknown): string {
    if (v === null) return "null";
    if (typeof v === "boolean") return v ? "true" : "false";
    if (typeof v === "number") {
      if (Number.isNaN(v)) return "NaN";
      if (v === Infinity) return "Infinity";
      if (v === -Infinity) return "-Infinity";
      if (Object.is(v, -0)) return "0";
      return v.toString();
    }
    if (typeof v === "string") {
      return String.fromCharCode(34) + Test.escapeJson(v) + String.fromCharCode(34);
    }
    if (v instanceof Uint8Array) {
      let hex = "";
      for (let i = 0, len = v.length; i < len; i += 1) {
        const b = v[i];
        const s = (b !== undefined ? b : 0).toString(16);
        hex += s.length < 2 ? "0" + s : s;
      }
      return hex;
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
    let jsonLine: string;
    if (verdict === "pass") {
      jsonLine = \'{"id":"\' + Test.escapeJson(id) + \'","name":"\' + Test.escapeJson(name) + \'","verdict":"pass"}\' + String.fromCharCode(10);
    } else {
      jsonLine = \'{"id":"\' + Test.escapeJson(id) + \'","name":"\' + Test.escapeJson(name) + \'","verdict":"fail","message":"\' + Test.escapeJson(message ?? "") + \'"}\' + String.fromCharCode(10);
    }
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
