import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

function read(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

const targetTrees = [
  "reference/ts/gen/boring/FnValuesOps.ts",
  "reference/kotlin/gen/boring/FnValuesOps.kt",
  "reference/swift/gen/boring/FnValuesOps.swift",
  "reference/dart/gen/lib/boring/fn_values_ops.dart",
  "reference/rust-gen/src/boring/fn_values_ops.rs",
];

describe("first-class function value generated trees", () => {
  test("all five targets emit the probe module", () => {
    for(const file of targetTrees) {
      expect(read(file)).toContain("FnValuesOps");
    }
  });

  test("TypeScript, Kotlin, Swift, and Dart keep static function storage", () => {
    const ts = read("reference/ts/gen/boring/FnValuesOps.ts");
    expect(ts).toContain("public static defaultTag: (id: number) => string =");
    expect(ts).toContain("defaultTag");

    const kotlin = read("reference/kotlin/gen/boring/FnValuesOps.kt");
    expect(kotlin).toContain("companion object");
    expect(kotlin).toContain("val defaultTag: (Int) -> String = fun(id: Int): String");
    expect(kotlin).toContain('return "tag" + id');

    const swift = read("reference/swift/gen/boring/FnValuesOps.swift");
    expect(swift).toContain("static let defaultTag: (Int32) -> String =");
    expect(swift).toContain("defaultTag");

    const dart = read("reference/dart/gen/lib/boring/fn_values_ops.dart");
    expect(dart).toContain("static final String Function(int) defaultTag =");
    expect(dart).toContain("defaultTag");
  });

  test("Rust uses one boxed representation and adapts indirect lengths", () => {
    const rust = read("reference/rust-gen/src/boring/fn_values_ops.rs");
    expect(rust).toContain("pub style_at: Rc<dyn Fn(u32) -> String>");
    expect(rust).toContain("pub resolver: Box<dyn NameResolver>");
    expect(rust).toContain("pub fn new(style_at: Rc<dyn Fn(u32) -> String>, resolver: Box<dyn NameResolver>)");
    expect(rust).toContain("pub fn apply_picker(values: &Vec<String>, pick: Rc<dyn Fn(u32) -> String>)");
    expect(rust).toContain("return pick(u32::wrapping_sub(u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0), 1));");
    expect(rust).toContain("pub fn make_prefixer(prefix: &str) -> Rc<dyn");
    expect(rust).toContain("Rc::new(move |suffix|");
    expect(rust).toContain("pub static DEFAULT_TAG: fn(i32) -> String =");
    expect(rust).not.toMatch(/(?:style_at|resolver): NameResolver/);

    const rustTests = read("reference/rust-gen/src/tests/fn_values_tests.rs");
    expect(rustTests).toContain("Box::new(BuiltInNameResolver::new())");
  });

  test("Rust's f32 tree carries the same function-value lowering", () => {
    const rust = read("reference/rust-f32-gen/src/boring/fn_values_ops.rs");
    expect(rust).toContain("Rc<dyn Fn(u32) -> String>");
    expect(rust).toContain("Box<dyn NameResolver>");
    expect(rust).toContain("Rc::new(move |suffix|");
    expect(rust).toContain("pub static DEFAULT_TAG: fn(i32) -> String =");
    expect(rust).toContain("u32::wrapping_sub(u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0), 1)");
  });
});

describe("static function field capture validation", () => {
  test("a capturing static initializer reports the ruled Rust error", async () => {
    const mutationRoot = fs.mkdtempSync(path.join(root, ".fn-values-mutation-"));
    try {
      const sourceRoot = path.join(mutationRoot, "samples");
      const sourceFile = path.join(sourceRoot, "boring/FnValuesOps.hx");
      const output = path.join(mutationRoot, "rust");
      const hxml = path.join(mutationRoot, "capture-rust.hxml");
      const source = read("samples/boring/FnValuesOps.hx");
      const variant = source
        .replace(
          "class FnValuesOps {",
          "class FnValuesOps {\n\tpublic static var capturedPrefix:String = \"captured\";",
        )
        .replace(
          'function(id:Int) return "tag" + id',
          "function(id:Int) return capturedPrefix + id",
        );
      expect(variant).toContain("capturedPrefix + id");

      fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
      fs.writeFileSync(sourceFile, variant);
      fs.writeFileSync(hxml, [
        "-lib reflaxe",
        "-lib boring",
        "-cp " + path.join(root, "src/reflaxe/rust/std-shadow"),
        "-cp " + path.join(root, "src/reflaxe/rust"),
        "-cp " + path.join(root, "samples"),
        "-cp " + sourceRoot,
        "--macro Intercept.run([\"" + sourceRoot + "\"])",
        "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
        "--macro rustcompiler.Compiler.use()",
        "-D rust-output=" + output,
        "boring.FnValuesOps",
        "",
      ].join("\n"));

      const proc = Bun.spawn(["haxe", hxml], {
        cwd: root,
        stdout: "pipe",
        stderr: "pipe",
      });
      const [exitCode, stdout, stderr] = await Promise.all([
        proc.exited,
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
      ]);
      expect(exitCode).not.toBe(0);
      expect(stdout + stderr).toContain("static function fields accept capture-free initializers only");
    } finally {
      fs.rmSync(mutationRoot, { recursive: true, force: true });
    }
  });
});
