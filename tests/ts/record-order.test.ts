import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

function read(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

/** The slice of a generated module from one class declaration onward. */
function classFrom(content: string, className: string): string {
  const start = content.indexOf(className);
  expect(start).toBeGreaterThanOrEqual(0);
  return content.slice(start);
}

/** The slice from a member signature to the end of the class slice. */
function memberFrom(region: string, signature: string): string {
  const start = region.indexOf(signature);
  expect(start).toBeGreaterThanOrEqual(0);
  return region.slice(start);
}

/** Checks that the reads appear in the given order inside the body. */
function expectOrdered(body: string, reads: string[]): void {
  let previous = -1;
  for(const read of reads) {
    const position = body.indexOf(read);
    expect(position).toBeGreaterThan(previous);
    previous = position;
  }
}

interface MemberTree {
  file: string;
  signature: string;
}

const memberTrees: MemberTree[] = [
  { file: "reference/ts/gen/boring/RecordOrderOps.ts", signature: "public toString(): string" },
  { file: "reference/swift/gen/boring/RecordOrderOps.swift", signature: "func toString() -> String" },
  { file: "reference/swift-f32/gen/boring/RecordOrderOps.swift", signature: "func toString() -> String" },
  { file: "reference/dart/gen/lib/boring/record_order_ops.dart", signature: "String toString()" },
  { file: "reference/rust-gen/src/boring/record_order_ops.rs", signature: "pub fn to_string(&self) -> String" },
  { file: "reference/rust-f32-gen/src/boring/record_order_ops.rs", signature: "pub fn to_string(&self) -> String" },
];

function fieldReads(file: string): string[] {
  return file.includes("swift") || file.includes("rust")
    ? ["self.a", "self.b", "self.c"]
    : ["this.a", "this.b", "this.c"];
}

describe("record print field order generated trees", () => {
  test("four non-native targets synthesize the member for both classes in declaration order", () => {
    for(const tree of memberTrees) {
      const content = read(tree.file);
      const reads = fieldReads(tree.file);
      for(const className of ["RecordOrderShifted", "RecordOrderAligned"]) {
        const body = memberFrom(classFrom(content, className), tree.signature);
        expectOrdered(body, reads);
      }
    }
  });

  test("Kotlin overrides the native print only for the reordered class", () => {
    for(const file of [
      "reference/kotlin/gen/boring/RecordOrderOps.kt",
      "reference/kotlin-f32/gen/boring/RecordOrderOps.kt",
    ]) {
      const content = read(file);
      expect(content).toContain("data class RecordOrderShifted(val a: Int, val c: String, val b: Int = 0)");
      const shifted = memberFrom(classFrom(content, "RecordOrderShifted"), "override fun toString(): String");
      expectOrdered(shifted, ["this.a", "this.b", "this.c"]);

      const alignedStart = content.indexOf("RecordOrderAligned");
      const alignedEnd = content.indexOf("RecordOrderOps", alignedStart);
      expect(alignedStart).toBeGreaterThanOrEqual(0);
      expect(alignedEnd).toBeGreaterThan(alignedStart);
      const aligned = content.slice(alignedStart, alignedEnd);
      expect(aligned).toContain("RecordOrderAligned(val a: Int, val b: Int, val c: String)");
      expect(aligned).not.toContain("toString");
    }
  });
});

interface MutationTarget {
  compilerClass: string;
  define: string;
  file: string;
  id: string;
  shadow: string;
  shadowParent: string;
}

const kotlinTarget: MutationTarget = {
  compilerClass: "kotlincompiler.Compiler.use()",
  define: "kotlin-output",
  file: "boring/RecordOrderOps.kt",
  id: "kotlin",
  shadow: "packages/compiler/reflaxe/kotlin/std-shadow",
  shadowParent: "packages/compiler/reflaxe/kotlin",
};

const tsTarget: MutationTarget = {
  compilerClass: "tscompiler.Compiler.use()",
  define: "ts-output",
  file: "boring/RecordOrderOps.ts",
  id: "ts",
  shadow: "packages/compiler/reflaxe/ts/std-shadow",
  shadowParent: "packages/compiler/reflaxe/ts",
};

interface CompileResult {
  code: number;
  output: string;
}

/** Writes a variant of samples/boring/RecordOrderOps.hx and compiles it. */
async function compileVariant(
  rootDir: string,
  variant: "aligned-fields" | "non-field-parameter",
  target: MutationTarget,
): Promise<CompileResult> {
  const source = read("samples/boring/RecordOrderOps.hx");
  let variantSource: string;
  if(variant === "aligned-fields") {
    // Declaring the shifted fields in constructor order removes the
    // reorder, so the native print and the member agree again.
    variantSource = source.replace(
      "    public final a:Int;\n    public final b:Int;\n    public final c:String;\n\n    public function new(a:Int, c:String, ?b:Int) {",
      "    public final a:Int;\n    public final c:String;\n    public final b:Int;\n\n    public function new(a:Int, c:String, ?b:Int) {",
    );
    expect(variantSource).not.toBe(source);
  } else {
    variantSource = source.replace(
      "    public function new(a:Int, b:Int, c:String) {",
      "    public function new(a:Int, b:Int, c:String, d:Int) {",
    );
    expect(variantSource).not.toBe(source);
  }

  const sourceRoot = path.join(rootDir, variant, "samples");
  const sourceFile = path.join(sourceRoot, "boring/RecordOrderOps.hx");
  const output = path.join(rootDir, variant, target.id);
  const hxml = path.join(rootDir, `${variant}-${target.id}.hxml`);
  fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
  fs.writeFileSync(sourceFile, variantSource);
  fs.writeFileSync(hxml, [
    "-lib reflaxe",
    "-lib boring",
    `-cp ${path.join(root, target.shadow)}`,
    `-cp ${path.join(root, target.shadowParent)}`,
    `-cp ${path.join(root, "samples")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    `--macro ${target.compilerClass}`,
    `-D ${target.define}=${output}`,
    "boring.RecordOrderOps",
    "",
  ].join("\n"));

  const proc = Bun.spawn(["haxe", hxml], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [code, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  return { code, output: stdout + stderr };
}

describe("record print field order mutations", () => {
  test("a constructor parameter without a field stops the compilation", async () => {
    const mutationRoot = fs.mkdtempSync(path.join(root, ".record-order-mutation-"));
    try {
      const result = await compileVariant(mutationRoot, "non-field-parameter", tsTarget);
      expect(result.code).not.toBe(0);
      expect(result.output).toContain("@:dataClass requires every constructor parameter to be a class field");
    } finally {
      fs.rmSync(mutationRoot, { recursive: true, force: true });
    }
  }, 120_000);

  test("aligning the field declarations removes the Kotlin explicit member", async () => {
    const mutationRoot = fs.mkdtempSync(path.join(root, ".record-order-mutation-"));
    try {
      const result = await compileVariant(mutationRoot, "aligned-fields", kotlinTarget);
      expect(result.code).toBe(0);
      expect(result.output).toBe("");
      const generated = read(path.relative(root, path.join(mutationRoot, "aligned-fields", kotlinTarget.id, kotlinTarget.file)));
      expect(generated).toContain("data class RecordOrderShifted");
      expect(generated).not.toContain("override fun toString");
    } finally {
      fs.rmSync(mutationRoot, { recursive: true, force: true });
    }
  }, 120_000);
});
