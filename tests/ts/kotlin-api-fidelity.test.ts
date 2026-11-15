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

  test("the value-class marker emits a JvmInline wrapper and the unmarked abstract keeps erasure", () => {
    const sourceRoot = fs.mkdtempSync(path.join(root, ".kotlin-fidelity-mutation-"));
    const output = path.join(sourceRoot, "out");
    try {
      fs.mkdirSync(path.join(sourceRoot, "mutation"), { recursive: true });
      fs.writeFileSync(path.join(sourceRoot, "mutation/MarkedId.hx"), `package mutation;

@:valueClass
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
});

