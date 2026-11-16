import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");
const markerError = "value type markers accept single-field abstracts over a primitive representation only";

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

interface MutationTarget {
  compiler: string;
  define: string;
  id: string;
  shadow: string;
}

interface MutationResult {
  exitCode: number;
  output: string;
}

const mutationTargets: MutationTarget[] = [
  { compiler: "tscompiler.Compiler.use()", define: "ts-output", id: "ts", shadow: "packages/compiler/reflaxe/ts/std-shadow" },
  { compiler: "kotlincompiler.Compiler.use()", define: "kotlin-output", id: "kotlin", shadow: "packages/compiler/reflaxe/kotlin/std-shadow" },
  { compiler: "swiftcompiler.Compiler.use()", define: "swift-output", id: "swift", shadow: "packages/compiler/reflaxe/swift/std-shadow" },
  { compiler: "dartcompiler.Compiler.use()", define: "dart-output", id: "dart", shadow: "packages/compiler/reflaxe/dart/std-shadow" },
  { compiler: "rustcompiler.Compiler.use()", define: "rust-output", id: "rust", shadow: "packages/compiler/reflaxe/rust/std-shadow" },
];

const invalidShapes = {
  "non-primitive representation": `package mutation;

@:valueType
abstract Invalid(Array<Int>) from Array<Int> {
  public function new(value:Array<Int>) this = value;
}
`,
  "generic abstract": `package mutation;

@:valueType
abstract Invalid<T>(T) from T {
  public function new(value:T) this = value;
}
`,
  "class declaration": `package mutation;

@:valueType
class Invalid {
  public function new() {}
}
`,
} as const;

function mutationHxml(sourceRoot: string, output: string, target: MutationTarget): string {
  return [
    "-lib reflaxe",
    "-lib boring",
    `-cp ${path.join(root, target.shadow)}`,
    `-cp ${path.join(root, target.shadow.replace("/std-shadow", ""))}`,
    `-cp ${path.join(root, "samples")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    `--macro ${target.compiler}`,
    `-D ${target.define}=${output}`,
    "mutation.Invalid",
    "",
  ].join("\n");
}

function runMutation(sourceRoot: string, output: string, target: MutationTarget): MutationResult {
  const hxml = path.join(path.dirname(sourceRoot), `${target.id}.hxml`);
  fs.writeFileSync(hxml, mutationHxml(sourceRoot, output, target));
  const process = Bun.spawnSync(["haxe", hxml], { cwd: root });
  return {
    exitCode: process.exitCode,
    output: process.stdout.toString() + process.stderr.toString(),
  };
}

// A value wrapper whose members cover the three emission shapes the Swift and
// Dart wrappers must distinguish: a plain static factory, an implicit-cast
// static factory, and an instance method that throws. The Swift factory and
// the throwing instance method both need the throws marker; the Dart
// extension type needs static on the two factories only.
const staticMemberShape = `package mutation;

class BlankFaceException extends haxe.Exception {
  public function new(message:String) super(message);
}

@:valueType
abstract StaticFace(String) from String {
  public inline function new(value:String) this = value;

  public static function of(value:String):StaticFace {
    if(StringTools.trim(value) == "") throw new BlankFaceException("blank");
    return new StaticFace(value);
  }

  @:from public static function fromString(value:String):StaticFace
    return of(value);

  public function validate():StaticFace {
    if(this.length == 0) throw new BlankFaceException("empty");
    return this;
  }

  public function toString():String return this;
}

class StaticFaceConsumer {
  public static function run(value:StaticFace):StaticFace return value.validate();
}
`;

function staticMemberHxml(sourceRoot: string, output: string, target: MutationTarget): string {
  const runtimeDefines = target.id === "dart"
    ? ["-D runtime-import=@boring/runtime", "-D runtime-emit=."]
    : [];
  return [
    "-lib reflaxe",
    "-lib boring",
    `-cp ${path.join(root, target.shadow)}`,
    `-cp ${path.join(root, target.shadow.replace("/std-shadow", ""))}`,
    `-cp ${path.join(root, "samples")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    `--macro ${target.compiler}`,
    ...runtimeDefines,
    `-D ${target.define}=${output}`,
    `-D ${target.define.replace("-output", "-test-output")}=${output}-tests`,
    "mutation.StaticFace",
    "",
  ].join("\n");
}

describe("value wrapper generated trees", () => {
  test("renders the five target representations and member forms", () => {
    const ts = read("reference/ts/gen/boring/ValueTypeOps.ts");
    expect(ts).toContain("export type Ic = number;");
    expect(ts).toContain("export function toPx(value: Ic, emPx: number): number");
    expect(ts).toContain("export function plus(a: Ic, b: Ic): Ic");
    expect(ts).toContain("export function negate(a: Ic): Ic");
    expect(ts).toContain("export const ZERO: Ic = 0.0;");
    expect(ts).toContain("export type FontFaceId = string;");
    expect(ts).toContain("export function makeFontFaceId(value: string): FontFaceId");
    expect(ts).not.toContain("class Ic");

    const tsConsumer = read("reference/ts/gen-tests/boring/ValueTypeConsumer.test.ts");
    expect(tsConsumer).toContain("const total = plus(first, ZERO);");
    expect(tsConsumer).toContain("return toString(id);");

    const kotlin = read("reference/kotlin/gen/boring/ValueTypeOps.kt");
    expect(kotlin).toContain("@JvmInline\nvalue class Ic(val count: Double)");
    expect(kotlin).toContain("operator fun plus(other: Ic): Ic");
    expect(kotlin).toContain("operator fun unaryMinus(): Ic");
    expect(kotlin).toContain("companion object");
    expect(kotlin).toContain("val ZERO: Ic = Ic(0.0)");

    withTargetTree("swift", "value-type: renders the five target representations and member forms", () => {
      const swift = read("reference/swift/gen/boring/ValueTypeOps.swift");
      expect(swift).toContain("struct Ic: Equatable, Hashable");
      expect(swift).toContain("let count: Double");
      expect(swift).toContain("static func +(lhs: Ic, rhs: Ic) -> Ic");
      expect(swift).toContain("static prefix func -(value: Ic) -> Ic");
      expect(swift).toContain("struct FontFaceId: Equatable, Hashable, CustomStringConvertible");
    });

    const dart = read("reference/dart/gen/lib/boring/value_type_ops.dart");
    expect(dart).toContain("extension type Ic(double count)");
    expect(dart).toContain("Ic operator +(Ic other)");
    expect(dart).toContain("Ic operator -()");
    expect(dart).toContain("static final Ic ZERO = Ic(0.0)");
    expect(dart).toContain("FontFaceId makeFontFaceId(String value)");

    const rust = read("reference/rust/gen/boring/value_type_ops.rs");
    // The wrapper stores the crate's float alias, so the width cannot be
    // pinned in the struct body; it is ruled once by the cfg-gated alias in
    // lib.rs, which keeps the two trees from drifting apart.
    expect(rust).toContain("#[derive(Debug, Clone, PartialEq)]\npub struct Ic(pub crate::TiqianFloat);");
    expect(rust).not.toContain("pub struct Ic(pub f64);");
    expect(rust).not.toContain("pub struct Ic(pub f32);");
    expect(rust).not.toContain("pub struct Ic(pub crate::TiqianFloat);\n\nimpl Eq");
    const rustLib = read("reference/rust/gen/lib.rs");
    expect(rustLib).toContain('#[cfg(feature = "f32")]\npub type TiqianFloat = f32;');
    expect(rustLib).toContain('#[cfg(not(feature = "f32"))]\npub type TiqianFloat = f64;');
    expect(rust).toContain("impl std::ops::Add for Ic");
    expect(rust).toContain("impl std::ops::Neg for Ic");
    expect(rust).toContain("impl std::fmt::Display for FontFaceId");
    expect(rust).toContain("#[derive(Debug, Clone, PartialEq, Eq, Hash)]\npub struct FontFaceId(pub UString);");

    const rustF32 = read("reference/rust-f32/gen/boring/value_type_ops.rs");
    expect(rustF32).toContain("#[derive(Debug, Clone, PartialEq)]\npub struct Ic(pub crate::TiqianFloat);");
    expect(rustF32).not.toContain("pub struct Ic(pub f32);");
    expect(rustF32).not.toContain("pub struct Ic(pub crate::TiqianFloat);\n\nimpl Eq");
    const rustF32Lib = read("reference/rust-f32/gen/lib.rs");
    expect(rustF32Lib).toContain('#[cfg(feature = "f32")]\npub type TiqianFloat = f32;');
  });

  test("rejects each invalid marker shape with the ruled error on every target", () => {
    const mutationRoot = fs.mkdtempSync(path.join(root, ".value-type-mutation-"));
    try {
      for(const [name, source] of Object.entries(invalidShapes)) {
        const sourceRoot = path.join(mutationRoot, name.replaceAll(" ", "-"));
        fs.mkdirSync(path.join(sourceRoot, "mutation"), { recursive: true });
        fs.writeFileSync(path.join(sourceRoot, "mutation/Invalid.hx"), source);
        for(const target of mutationTargets) {
          const output = path.join(sourceRoot, target.id);
          const result = runMutation(sourceRoot, output, target);
          expect(result.exitCode).not.toBe(0);
          expect(result.output).toContain(markerError);
        }
      }
    } finally {
      fs.rmSync(mutationRoot, { recursive: true, force: true });
    }
    // Fifteen haxe macro-compiler runs (three invalid marker shapes across
    // the five targets, run synchronously) measured at 353.7 s total
    // (baseline machine, quiet window); 720_000 keeps ≥2× margin. The
    // explicit timeout raises only the harness patience for those
    // subprocesses, never the asserted behavior.
  }, 720_000);

  test("renders value wrapper static members as static with Swift throws", () => {
    const sourceRoot = fs.mkdtempSync(path.join(root, ".value-type-mutation-static-"));
    try {
      fs.mkdirSync(path.join(sourceRoot, "mutation"), { recursive: true });
      fs.writeFileSync(path.join(sourceRoot, "mutation/StaticFace.hx"), staticMemberShape);
      for(const target of mutationTargets) {
        if(target.id !== "swift" && target.id !== "dart") continue;
        const hxml = path.join(sourceRoot, `${target.id}.hxml`);
        fs.writeFileSync(hxml, staticMemberHxml(sourceRoot, path.join(sourceRoot, target.id), target));
        const compile = Bun.spawnSync(["haxe", hxml], { cwd: root });
        expect(compile.exitCode, compile.stdout.toString() + compile.stderr.toString()).toBe(0);
      }
      const swift = fs.readFileSync(path.join(sourceRoot, "swift/mutation/StaticFace.swift"), "utf8");
      expect(swift).toContain("public static func of(_ value: [UInt16]) throws -> StaticFace {");
      expect(swift).toContain("public static func fromString(_ value: [UInt16]) throws -> StaticFace {");
      expect(swift).toContain("public func validate() throws -> StaticFace {");
      const dart = fs.readFileSync(path.join(sourceRoot, "dart/lib/mutation/static_face.dart"), "utf8");
      expect(dart).toContain("static StaticFace of(String value) {");
      expect(dart).toContain("static StaticFace fromString(String value) {");
      expect(dart).toContain("StaticFace validate() {");
      expect(read("reference/swift/gen/boring/StaticStateOps.swift")).toContain("public static func install(_ value: [UInt16]) -> Void {");
    } finally {
      fs.rmSync(sourceRoot, { recursive: true, force: true });
    }
  }, 120_000);
});
