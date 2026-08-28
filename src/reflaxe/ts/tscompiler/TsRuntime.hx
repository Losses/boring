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

interface MapEntry<V> {
  key: number;
  idx: number;
  value: V;
}

export class SortedMapBuilder<V> {
  private entries: MapEntry<V>[];

  constructor() {
    this.entries = [];
  }

  put(key: number, value: V): void {
    this.entries.push({ key, idx: this.entries.length, value });
  }

  get(key: number): V | null {
    for (let i = this.entries.length - 1; i >= 0; i -= 1) {
      if (this.entries[i]!.key === key) {
        return this.entries[i]!.value;
      }
    }
    return null;
  }

  build(): SortedMap<V> {
    if (this.entries.length === 0) {
      return new SortedMap<V>([], []);
    }
    const total = this.entries.length;
    for (let i = 1; i < total; i += 1) {
      const current = this.entries[i]!;
      let j = i - 1;
      while (j >= 0) {
        const prev = this.entries[j]!;
        if (prev.key > current.key || (prev.key === current.key && prev.idx > current.idx)) {
          this.entries[j + 1] = prev;
          j -= 1;
        } else {
          break;
        }
      }
      this.entries[j + 1] = current;
    }
    const keys: number[] = [];
    const values: V[] = [];
    let i = 0;
    while (i < total) {
      let j = i;
      while (j + 1 < total && this.entries[j + 1]!.key === this.entries[i]!.key) {
        j += 1;
      }
      const entry = this.entries[j]!;
      keys.push(entry.key);
      values.push(entry.value);
      i = j + 1;
    }
    return new SortedMap<V>(keys, values);
  }
}

export class SortedMap<V> {
  private keys: number[];
  private values: V[];

  constructor(keys: number[], values: V[]) {
    this.keys = keys;
    this.values = values;
  }

  static builder<V>(): SortedMapBuilder<V> {
    return new SortedMapBuilder<V>();
  }

  get(key: number): V | null {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      if (midVal < key) {
        low = mid + 1;
      } else if (midVal > key) {
        high = mid - 1;
      } else {
        return this.values[mid] !== undefined ? this.values[mid]! : null;
      }
    }
    return null;
  }

  has(key: number): boolean {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      if (midVal < key) {
        low = mid + 1;
      } else if (midVal > key) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  size(): number {
    return this.keys.length;
  }

  keyAt(index: number): number {
    return this.keys[index]!;
  }

  valueAt(index: number): V {
    return this.values[index]!;
  }
}

export class SortedSetBuilder {
  private keys: number[];

  constructor() {
    this.keys = [];
  }

  put(key: number): void {
    this.keys.push(key);
  }

  build(): SortedSet {
    if (this.keys.length === 0) {
      return new SortedSet([]);
    }
    const count = this.keys.length;
    for (let i = 1; i < count; i += 1) {
      const current = this.keys[i]!;
      let j = i - 1;
      while (j >= 0 && this.keys[j]! > current) {
        this.keys[j + 1] = this.keys[j]!;
        j -= 1;
      }
      this.keys[j + 1] = current;
    }
    const distinct: number[] = [];
    for (let i = 0; i < count; i += 1) {
      const k = this.keys[i]!;
      if (distinct.length === 0 || distinct[distinct.length - 1] !== k) {
        distinct.push(k);
      }
    }
    return new SortedSet(distinct);
  }
}

export class SortedSet {
  private keys: number[];

  constructor(keys: number[]) {
    this.keys = keys;
  }

  static builder(): SortedSetBuilder {
    return new SortedSetBuilder();
  }

  has(key: number): boolean {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      if (midVal < key) {
        low = mid + 1;
      } else if (midVal > key) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  size(): number {
    return this.keys.length;
  }

  at(index: number): number {
    return this.keys[index]!;
  }
}

interface MapStrEntry<V> {
  key: string;
  idx: number;
  value: V;
}

export class SortedMapStrBuilder<V> {
  private entries: MapStrEntry<V>[];

  constructor() {
    this.entries = [];
  }

  put(key: string, value: V): void {
    this.entries.push({ key, idx: this.entries.length, value });
  }

  get(key: string): V | null {
    for (let i = this.entries.length - 1; i >= 0; i -= 1) {
      if (this.entries[i]!.key === key) {
        return this.entries[i]!.value;
      }
    }
    return null;
  }

  build(): SortedMapStr<V> {
    if (this.entries.length === 0) {
      return new SortedMapStr<V>([], []);
    }
    const total = this.entries.length;
    for (let i = 1; i < total; i += 1) {
      const current = this.entries[i]!;
      let j = i - 1;
      while (j >= 0) {
        const prev = this.entries[j]!;
        if (prev.key > current.key || (prev.key === current.key && prev.idx > current.idx)) {
          this.entries[j + 1] = prev;
          j -= 1;
        } else {
          break;
        }
      }
      this.entries[j + 1] = current;
    }
    const keys: string[] = [];
    const values: V[] = [];
    let i = 0;
    while (i < total) {
      let j = i;
      while (j + 1 < total && this.entries[j + 1]!.key === this.entries[i]!.key) {
        j += 1;
      }
      const entry = this.entries[j]!;
      keys.push(entry.key);
      values.push(entry.value);
      i = j + 1;
    }
    return new SortedMapStr<V>(keys, values);
  }
}

export class SortedMapStr<V> {
  private keys: string[];
  private values: V[];

  constructor(keys: string[], values: V[]) {
    this.keys = keys;
    this.values = values;
  }

  static builder<V>(): SortedMapStrBuilder<V> {
    return new SortedMapStrBuilder<V>();
  }

  get(key: string): V | null {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      if (midVal < key) {
        low = mid + 1;
      } else if (midVal > key) {
        high = mid - 1;
      } else {
        return this.values[mid] !== undefined ? this.values[mid]! : null;
      }
    }
    return null;
  }

  has(key: string): boolean {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      if (midVal < key) {
        low = mid + 1;
      } else if (midVal > key) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  size(): number {
    return this.keys.length;
  }

  keyAt(index: number): string {
    return this.keys[index]!;
  }

  valueAt(index: number): V {
    return this.values[index]!;
  }
}

export class SortedSetStrBuilder {
  private keys: string[];

  constructor() {
    this.keys = [];
  }

  put(key: string): void {
    this.keys.push(key);
  }

  build(): SortedSetStr {
    if (this.keys.length === 0) {
      return new SortedSetStr([]);
    }
    const count = this.keys.length;
    for (let i = 1; i < count; i += 1) {
      const current = this.keys[i]!;
      let j = i - 1;
      while (j >= 0 && this.keys[j]! > current) {
        this.keys[j + 1] = this.keys[j]!;
        j -= 1;
      }
      this.keys[j + 1] = current;
    }
    const distinct: string[] = [];
    for (let i = 0; i < count; i += 1) {
      const k = this.keys[i]!;
      if (distinct.length === 0 || distinct[distinct.length - 1] !== k) {
        distinct.push(k);
      }
    }
    return new SortedSetStr(distinct);
  }
}

export class SortedSetStr {
  private keys: string[];

  constructor(keys: string[]) {
    this.keys = keys;
  }

  static builder(): SortedSetStrBuilder {
    return new SortedSetStrBuilder();
  }

  has(key: string): boolean {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      if (midVal < key) {
        low = mid + 1;
      } else if (midVal > key) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  size(): number {
    return this.keys.length;
  }

  at(index: number): string {
    return this.keys[index]!;
  }
}

interface MapByKeyEntry<K, V> {
  key: K;
  idx: number;
  value: V;
}

export type Comparator<T> = (a: T, b: T) => number;

export class SortedMapByKeyBuilder<K, V> {
  private entries: MapByKeyEntry<K, V>[];
  private compare: Comparator<K>;

  constructor(compare: Comparator<K>) {
    this.entries = [];
    this.compare = compare;
  }

  put(key: K, value: V): void {
    this.entries.push({ key, idx: this.entries.length, value });
  }

  get(key: K): V | null {
    for (let i = this.entries.length - 1; i >= 0; i -= 1) {
      if (this.compare(this.entries[i]!.key, key) === 0) {
        return this.entries[i]!.value;
      }
    }
    return null;
  }

  build(): SortedMapByKey<K, V> {
    if (this.entries.length === 0) {
      return new SortedMapByKey<K, V>([], [], this.compare);
    }
    const total = this.entries.length;
    for (let i = 1; i < total; i += 1) {
      const current = this.entries[i]!;
      let j = i - 1;
      while (j >= 0) {
        const prev = this.entries[j]!;
        const cmp = this.compare(prev.key, current.key);
        if (cmp > 0 || (cmp === 0 && prev.idx > current.idx)) {
          this.entries[j + 1] = prev;
          j -= 1;
        } else {
          break;
        }
      }
      this.entries[j + 1] = current;
    }
    const keys: K[] = [];
    const values: V[] = [];
    let i = 0;
    while (i < total) {
      let j = i;
      while (j + 1 < total && this.compare(this.entries[j + 1]!.key, this.entries[i]!.key) === 0) {
        j += 1;
      }
      const entry = this.entries[j]!;
      keys.push(entry.key);
      values.push(entry.value);
      i = j + 1;
    }
    return new SortedMapByKey<K, V>(keys, values, this.compare);
  }
}

export class SortedMapByKey<K, V> {
  private keys: K[];
  private values: V[];
  private compare: Comparator<K>;

  constructor(keys: K[], values: V[], compare: Comparator<K>) {
    this.keys = keys;
    this.values = values;
    this.compare = compare;
  }

  static builder<K, V>(compare: Comparator<K>): SortedMapByKeyBuilder<K, V> {
    return new SortedMapByKeyBuilder<K, V>(compare);
  }

  get(key: K): V | null {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      const cmp = this.compare(midVal, key);
      if (cmp < 0) {
        low = mid + 1;
      } else if (cmp > 0) {
        high = mid - 1;
      } else {
        return this.values[mid] !== undefined ? this.values[mid]! : null;
      }
    }
    return null;
  }

  has(key: K): boolean {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      const cmp = this.compare(midVal, key);
      if (cmp < 0) {
        low = mid + 1;
      } else if (cmp > 0) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  size(): number {
    return this.keys.length;
  }

  keyAt(index: number): K {
    return this.keys[index]!;
  }

  valueAt(index: number): V {
    return this.values[index]!;
  }
}

export class SortedSetByKeyBuilder<K> {
  private keys: K[];
  private compare: Comparator<K>;

  constructor(compare: Comparator<K>) {
    this.keys = [];
    this.compare = compare;
  }

  put(key: K): void {
    this.keys.push(key);
  }

  build(): SortedSetByKey<K> {
    if (this.keys.length === 0) {
      return new SortedSetByKey<K>([], this.compare);
    }
    const count = this.keys.length;
    for (let i = 1; i < count; i += 1) {
      const current = this.keys[i]!;
      let j = i - 1;
      while (j >= 0 && this.compare(this.keys[j]!, current) > 0) {
        this.keys[j + 1] = this.keys[j]!;
        j -= 1;
      }
      this.keys[j + 1] = current;
    }
    const distinct: K[] = [];
    for (let i = 0; i < count; i += 1) {
      const k = this.keys[i]!;
      if (distinct.length === 0 || this.compare(distinct[distinct.length - 1]!, k) !== 0) {
        distinct.push(k);
      }
    }
    return new SortedSetByKey<K>(distinct, this.compare);
  }
}

export class SortedSetByKey<K> {
  private keys: K[];
  private compare: Comparator<K>;

  constructor(keys: K[], compare: Comparator<K>) {
    this.keys = keys;
    this.compare = compare;
  }

  static builder<K>(compare: Comparator<K>): SortedSetByKeyBuilder<K> {
    return new SortedSetByKeyBuilder<K>(compare);
  }

  has(key: K): boolean {
    let low = 0;
    let high = this.keys.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      const midVal = this.keys[mid]!;
      const cmp = this.compare(midVal, key);
      if (cmp < 0) {
        low = mid + 1;
      } else if (cmp > 0) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  size(): number {
    return this.keys.length;
  }

  at(index: number): K {
    return this.keys[index]!;
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

export const UString = {
  count(s: string): number {
    let total = 0;
    let i = 0;
    while (i < s.length) {
      const cp = s.codePointAt(i)!;
      i += cp > 0xffff ? 2 : 1;
      total += 1;
    }
    return total;
  },
  at(s: string, index: number): number | null {
    if (index < 0) return null;
    let remaining = index;
    let i = 0;
    while (i < s.length) {
      const cp = s.codePointAt(i)!;
      if (remaining === 0) return cp;
      remaining -= 1;
      i += cp > 0xffff ? 2 : 1;
    }
    return null;
  },
  slice(s: string, from: number, to: number): string {
    const total = UString.count(s);
    const start = from < 0 ? 0 : from > total ? total : from;
    const end = to > total ? total : to < 0 ? 0 : to;
    if (start >= end) return "";
    let unitStart = 0;
    let pos = 0;
    let i = 0;
    while (pos < end) {
      if (pos === start) unitStart = i;
      const cp = s.codePointAt(i)!;
      i += cp > 0xffff ? 2 : 1;
      pos += 1;
    }
    return s.substring(unitStart, i);
  },
  toCodePoints(s: string): number[] {
    const out: number[] = [];
    let i = 0;
    while (i < s.length) {
      const cp = s.codePointAt(i)!;
      out.push(cp);
      i += cp > 0xffff ? 2 : 1;
    }
    return out;
  },
  fromCodePoint(code: number): string {
    return String.fromCodePoint(code);
  },
  fromCodePoints(codes: number[]): string {
    let out = "";
    for (let i = 0, len = codes.length; i < len; i += 1) {
      out += String.fromCodePoint(codes[i]!);
    }
    return out;
  },
};
';
}
#end
