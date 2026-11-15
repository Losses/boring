import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
    The Kotlin public-API fidelity rules: a generated record carries the
    data-class copy, a data-class record keeps only Kotlin's synthesized one,
    and the value-class marker keeps an opaque primitive wrapper as a Kotlin
    value class while an unmarked abstract keeps the erasure ruling.
**/

const root = path.resolve(__dirname, "../..");

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

describe("Kotlin public-API fidelity", () => {
  test("a generated record carries the data-class copy", () => {
    const kotlin = read("reference/kotlin/gen/boring/NullBoolStyle.kt");
    expect(kotlin).toContain("fun copy(italic: Boolean? = this.italic): NullBoolStyle = NullBoolStyle(italic)");
  });

  test("a data-class record keeps Kotlin's synthesized copy only", () => {
    const kotlin = read("reference/kotlin/gen-tests/boring/ValueTypeConsumer.kt");
    expect(kotlin).toContain("data class OptionalIcRecord");
    expect(kotlin).not.toContain("fun copy(");
  });

  test("the value-type marker emits a JvmInline wrapper and the unmarked abstract keeps erasure", () => {
    const sourceRoot = fs.mkdtempSync(path.join(root, ".kotlin-fidelity-mutation-"));
    const output = path.join(sourceRoot, "out");
    try {
      fs.mkdirSync(path.join(sourceRoot, "mutation"), { recursive: true });
      fs.writeFileSync(path.join(sourceRoot, "mutation/MarkedId.hx"), `package mutation;

@:valueType
abstract MarkedId(String) {
    public static function of(value:String):MarkedId
        return cast(value, MarkedId);

    @:from public static function fromString(value:String):MarkedId
        return of(value);

    public var value(get, never):String;

    inline function get_value():String
        return this;

    public function toString():String
        return this;
}

abstract ErasedId(String) {
    public static function of(value:String):ErasedId
        return cast(value, ErasedId);

    public function toString():String
        return this;
}
`);
      fs.writeFileSync(path.join(sourceRoot, "mutation/Consumer.hx"), `package mutation;

import mutation.MarkedId;

class Consumer {
    public static function render(id:MarkedId):String
        return id.toString();

    public static function renderErased(id:ErasedId):String
        return id.toString();
}
`);
      const hxml = path.join(sourceRoot, "kotlin.hxml");
      fs.writeFileSync(hxml, [
        "-lib reflaxe",
        "-lib boring",
        "-cp packages/compiler",
        "-cp packages/compiler/reflaxe/kotlin/std-shadow",
        "-cp packages/compiler/reflaxe/kotlin",
        `-cp ${sourceRoot}`,
        "-cp samples",
        `--macro Intercept.run(['samples', '${sourceRoot}'])`,
        "--macro kotlincompiler.Compiler.use()",
        `-D kotlin-output=${output}`,
        "-D runtime-import=boring.runtime",
        "-D runtime-emit=runtime",
        "mutation.Consumer",
        "",
      ].join("\n"));
      const result = Bun.spawnSync(["haxe", hxml], { cwd: root });
      const diagnostics = result.stderr.toString() + result.stdout.toString();
      expect(diagnostics).toBe("");
      const markedModule = fs.readFileSync(path.join(output, "mutation/MarkedId.kt"), "utf8");
      expect(markedModule).toContain("@JvmInline\nvalue class MarkedId(val value: String)");
      expect(markedModule).toContain("companion object");
      expect(markedModule).toContain("fun of(value: String): MarkedId");
      expect(markedModule).not.toContain("value class ErasedId");
      const consumer = fs.readFileSync(path.join(output, "mutation/Consumer.kt"), "utf8");
      expect(consumer).toContain("fun render(id: MarkedId): String");
      expect(consumer).toContain("fun renderErased(id: String): String");
    } finally {
      fs.rmSync(sourceRoot, { recursive: true, force: true });
    }
  }, 120_000);

  test("the resident Kotlin sorted tables implement Map and Set with no boundary conversion", () => {
    const runtime = read("reference/kotlin/gen/runtime/SortedTable.kt");
    expect(runtime).toContain("class SortedMapTable<K, V>(private val _keys: MutableList<K>, private val _values: MutableList<V>");
    expect(runtime).toContain(") : Map<K, V>");
    expect(runtime).toContain("class SortedSetTable<K>(private val _keys: MutableList<K>");
    expect(runtime).toContain(") : Set<K>");
    expect(runtime).toContain("override val size: Int get()");
    expect(runtime).toContain("override val keys: Set<K>");
    expect(runtime).toContain("override val values: Collection<V>");
    expect(runtime).toContain("override val entries: Set<Map.Entry<K, V>>");
    expect(runtime).toContain("override fun containsKey(key: K): Boolean");
    expect(runtime).toContain("override fun containsAll(elements: Collection<K>): Boolean");
    expect(runtime).toContain("fun keyAt(index: Int): K");
    expect(runtime).toContain("fun valueAt(index: Int): V");
    expect(runtime).toContain("fun at(index: Int): K");
    expect(runtime).toContain("fun has(key: K): Boolean");
    expect(runtime).not.toContain("fun size(): Int");

    const sourceRoot = fs.mkdtempSync(path.join(root, ".kotlin-table-conformance-"));
    try {
      const probe = path.join(sourceRoot, "Probe.kt");
      fs.writeFileSync(probe, `import boring.runtime.SortedMapTable
import boring.runtime.SortedSetTable

fun acceptsMap(m: Map<String, Int>): Int = m.size
fun acceptsSet(s: Set<Int>): Int = s.size

fun exercise(t: SortedMapTable<String, Int>, u: SortedSetTable<Int>): Int {
    val m: Map<String, Int> = t
    val s: Set<Int> = u
    return acceptsMap(t) + acceptsSet(u) + m.keys.size + m.values.size + m.entries.size + s.size
        + t.keyAt(0).length + u.at(0) + t.valueAt(0)
}
`);
      const jar = path.join(sourceRoot, "probe.jar");
      const result = Bun.spawnSync([
        "kotlinc",
        path.join(root, "reference/kotlin/gen/runtime/SortedTable.kt"),
        probe,
        "-d",
        jar,
      ]);
      const diagnostics = result.stderr.toString() + result.stdout.toString();
      expect(diagnostics).toBe("");
      expect(result.exitCode).toBe(0);
    } finally {
      fs.rmSync(sourceRoot, { recursive: true, force: true });
    }
  }, 180_000);
});

