import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

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

    const tsConsumer = read("reference/ts/gen/boring/ValueTypeConsumer.ts");
    expect(tsConsumer).toContain("const total = plus(first, ZERO);");
    expect(tsConsumer).toContain("return toString(id);");

    const kotlin = read("reference/kotlin/gen/boring/ValueTypeOps.kt");
    expect(kotlin).toContain("@JvmInline\nvalue class Ic(val count: Double)");
    expect(kotlin).toContain("operator fun plus(other: Ic): Ic");
    expect(kotlin).toContain("operator fun unaryMinus(): Ic");
    expect(kotlin).toContain("companion object");
    expect(kotlin).toContain("val ZERO: Ic = Ic(0.0)");

    const swift = read("reference/swift/gen/boring/ValueTypeOps.swift");
    expect(swift).toContain("struct Ic: Equatable, Hashable");
    expect(swift).toContain("let count: Double");
    expect(swift).toContain("static func +(lhs: Ic, rhs: Ic) -> Ic");
    expect(swift).toContain("static prefix func -(value: Ic) -> Ic");
    expect(swift).toContain("struct FontFaceId: Equatable, Hashable, CustomStringConvertible");

    const dart = read("reference/dart/gen/lib/boring/value_type_ops.dart");
    expect(dart).toContain("extension type Ic(double count)");
    expect(dart).toContain("Ic operator +(Ic other)");
    expect(dart).toContain("Ic operator -()");
    expect(dart).toContain("static final Ic ZERO = Ic(0.0)");
    expect(dart).toContain("FontFaceId makeFontFaceId(String value)");

    const rust = read("reference/rust-gen/src/boring/value_type_ops.rs");
    expect(rust).toContain("#[derive(Debug, Clone, PartialEq)]\npub struct Ic(pub f64);");
    expect(rust).not.toContain("pub struct Ic(pub f64);\n\nimpl Eq");
    expect(rust).toContain("impl std::ops::Add for Ic");
    expect(rust).toContain("impl std::ops::Neg for Ic");
    expect(rust).toContain("impl std::fmt::Display for FontFaceId");
    expect(rust).toContain("#[derive(Debug, Clone, PartialEq, Eq, Hash)]\npub struct FontFaceId(pub String);");

    const rustF32 = read("reference/rust-f32-gen/src/boring/value_type_ops.rs");
    expect(rustF32).toContain("#[derive(Debug, Clone, PartialEq)]\npub struct Ic(pub f32);");
    expect(rustF32).not.toContain("pub struct Ic(pub f32);\n\nimpl Eq");
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
  }, 120_000);
});
