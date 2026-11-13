import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree, type TargetId } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

/**
 * The Rust realization of a Haxe function value is the single-thread shape the
 * target policy fixes, not a threaded one:
 *
 *   docs/specs/target-semantic-policy.md:43-56 -- "Rust must not smuggle
 *   Arc/Mutex in to prepare for a possible future threaded host", and
 *   `Rc<RefCell<dyn FnMut(..) -> R>>` = function value,
 *   `Rc<RefCell<dyn Trait>>` = interface / shared interface.
 *
 * The assertions below therefore pin the Rc<RefCell<...>> spellings. They
 * previously pinned `Arc<dyn Fn(..) + Send + Sync>`, which no policy sanctions:
 * a threaded realization is a separate target policy, never this v1 one.
 */

const root = path.resolve(__dirname, "../..");

function read(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

const targetTrees: ReadonlyArray<{ readonly target: TargetId; readonly file: string }> = [
  { target: "ts", file: "reference/ts/gen/boring/FnValuesOps.ts" },
  { target: "kotlin", file: "reference/kotlin/gen/boring/FnValuesOps.kt" },
  { target: "swift", file: "reference/swift/gen/boring/FnValuesOps.swift" },
  { target: "dart", file: "reference/dart/gen/lib/boring/fn_values_ops.dart" },
  { target: "rust", file: "reference/rust/gen/boring/fn_values_ops.rs" },
];

describe("first-class function value generated trees", () => {
  test("all five targets emit the probe module", () => {
    for(const { target, file } of targetTrees) {
      withTargetTree(target, "fn-values: all five targets emit the probe module", () => {
        expect(read(file)).toContain("FnValuesOps");
      });
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

    withTargetTree("swift", "fn-values: TypeScript, Kotlin, Swift, and Dart keep static function storage", () => {
      const swift = read("reference/swift/gen/boring/FnValuesOps.swift");
      // Swift stores a Haxe String as Array<UInt16> (docs/architecture/
      // INTERFACE-REQUIREMENTS.md:235 "String <-> Array<UInt16>", restated for
      // the buffer at docs/specs/stdlib/08-string-buffer.md:132 and shown as a
      // value type at docs/specs/features/10-static-extension.md:152). The
      // closure type therefore ends in [UInt16], not in the native String.
      expect(swift).toContain("static let defaultTag: (Int32) -> [UInt16] =");
      expect(swift).toContain("defaultTag");
    });

    const dart = read("reference/dart/gen/lib/boring/fn_values_ops.dart");
    expect(dart).toContain("static final String Function(int) defaultTag =");
    expect(dart).toContain("defaultTag");
  });

  test("Rust uses one shared-handle representation and adapts indirect lengths", () => {
    const rust = read("reference/rust/gen/boring/fn_values_ops.rs");
    expect(rust).toContain("pub style_at: Rc<RefCell<dyn FnMut(u32) -> UString>>");
    expect(rust).toContain("pub resolver: Rc<RefCell<dyn NameResolver>>");
    expect(rust).toContain("pub fn new(style_at: Rc<RefCell<dyn FnMut(u32) -> UString>>, resolver: Rc<RefCell<dyn NameResolver>>) -> Rc<RefCell<Self>>");
    expect(rust).toContain("pub fn fn_values_ops_apply_picker(values: &Vec<UString>, pick: Rc<RefCell<dyn FnMut(u32) -> UString>>)");
    expect(rust).toContain("return pick.borrow_mut()(u32::wrapping_sub(u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0), 1));");
    expect(rust).toContain("pub fn fn_values_ops_make_prefixer(prefix: &UStr) -> Rc<RefCell<dyn FnMut(&UStr) -> UString + '_>>");
    expect(rust).toContain("Rc::new(RefCell::new(move |suffix: &UStr|");
    expect(rust).toContain("pub static FN_VALUES_OPS_DEFAULT_TAG: fn(u32) -> UString =");
    expect(rust).not.toMatch(/(?:style_at|resolver): NameResolver/);

    const rustTests = read("reference/rust/gen/tests/tests/fn_values_tests/tests/fn_values_tests.rs");
    expect(rustTests).toContain("Rc<RefCell<dyn NameResolver>> = BuiltInNameResolver::new()");
  });

  test("Rust's f32 tree carries the same function-value lowering", () => {
    const rust = read("reference/rust-f32/gen/boring/fn_values_ops.rs");
    expect(rust).toContain("Rc<RefCell<dyn FnMut(u32) -> UString>>");
    expect(rust).toContain("Rc<RefCell<dyn NameResolver>>");
    expect(rust).toContain("Rc::new(RefCell::new(move |suffix: &UStr|");
    expect(rust).toContain("pub static FN_VALUES_OPS_DEFAULT_TAG: fn(u32) -> UString =");
    expect(rust).toContain("u32::wrapping_sub(u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0), 1)");
  });

  test("Rust realizes every function-value position as one shared handle", () => {
    const rust = read("reference/rust/gen/boring/static_ref_ops.rs");
    expect(rust).toContain("pub fn static_ref_ops_take_fn(callback: Rc<RefCell<dyn FnMut(u32) -> UString>>)");
    expect(rust).toContain("let r#fn: Rc<RefCell<dyn FnMut(u32) -> UString>> = Rc::new(RefCell::new(StaticRefOps::static_ref_ops_render));");
    expect(rust).toContain("pub fn static_ref_ops_return_fn() -> Rc<RefCell<dyn FnMut(u32) -> UString + 'static>>");
    expect(rust).toContain("let cmp: Rc<RefCell<dyn FnMut(&UStr, &UStr) -> u32>> = Rc::new(RefCell::new(StaticRefStatics::static_ref_statics_compare_strings));");

    const sortedTable = read("reference/rust/gen/runtime/sorted_table.rs");
    expect(sortedTable).toContain("pub fn sorted_table_map_builder<K: Clone, V: Clone>(compare: Rc<RefCell<dyn FnMut(&K, &K) -> i32>>)");
    expect(sortedTable).toContain("pub compare: Rc<RefCell<dyn FnMut(&K, &K) -> i32>>");
  });

  test("Rust's f32 tree bounds the resident comparator", () => {
    const sortedTable = read("reference/rust-f32/gen/runtime/sorted_table.rs");
    expect(sortedTable).toContain("pub fn sorted_table_set_builder<K: Clone>(compare: Rc<RefCell<dyn FnMut(&K, &K) -> i32>>)");
    expect(sortedTable).toContain("pub compare: Rc<RefCell<dyn FnMut(&K, &K) -> i32>>");
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
        "-cp " + path.join(root, "packages/compiler/reflaxe/rust/std-shadow"),
        "-cp " + path.join(root, "packages/compiler/reflaxe/rust"),
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
    // One full haxe macro-compiler run (rust target) measured at 23.7 s
    // (baseline machine, quiet window); 60_000 keeps ≥2× margin. The explicit
    // timeout raises only the harness patience for that subprocess, never
    // the asserted behavior.
  }, 60_000);
});
