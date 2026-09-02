import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

interface SelfTarget {
  compiler: string;
  define: string;
  file: string;
  id: string;
  shadow: string;
}

const selfTargets: SelfTarget[] = [
  {
    compiler: "tscompiler.Compiler.use()",
    define: "ts-output",
    file: "boring/NoneDrawKind.ts",
    id: "ts",
    shadow: "src/reflaxe/ts/std-shadow",
  },
  {
    compiler: "kotlincompiler.Compiler.use()",
    define: "kotlin-output",
    file: "boring/NoneDrawKind.kt",
    id: "kotlin",
    shadow: "src/reflaxe/kotlin/std-shadow",
  },
  {
    compiler: "swiftcompiler.Compiler.use()",
    define: "swift-output",
    file: "boring/NoneDrawKind.swift",
    id: "swift",
    shadow: "src/reflaxe/swift/std-shadow",
  },
  {
    compiler: "dartcompiler.Compiler.use()",
    define: "dart-output",
    file: "lib/boring/none_draw_kind.dart",
    id: "dart",
    shadow: "src/reflaxe/dart/std-shadow",
  },
  {
    compiler: "rustcompiler.Compiler.use()",
    define: "rust-output",
    file: "boring/none_draw_kind.rs",
    id: "rust",
    shadow: "src/reflaxe/rust/std-shadow",
  },
];

async function generateSelfConstruction(
  mutationRoot: string,
  sourceRoot: string,
  target: SelfTarget,
): Promise<string> {
  const sourceFile = path.join(sourceRoot, "boring/NoneDrawKind.hx");
  const hxml = path.join(mutationRoot, `${target.id}.hxml`);
  const output = path.join(mutationRoot, target.id);
  fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
  fs.writeFileSync(sourceFile, [
    "package boring;",
    "",
    "class NoneDrawKind {",
    "  public static final instance:NoneDrawKind = new NoneDrawKind();",
    "  private function new() {}",
    "}",
    "",
  ].join("\n"));
  fs.writeFileSync(hxml, [
    "-lib reflaxe",
    "-lib boring",
    `-cp ${path.join(root, target.shadow)}`,
    `-cp ${path.join(root, target.shadow.replace("/std-shadow", ""))}`,
    `-cp ${path.join(root, "samples")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    `--macro ${target.compiler}`,
    `-D ${target.define}=${output}`,
    ...(target.id === "dart" ? [`-D dart-test-output=${output}-tests`] : []),
    "boring.NoneDrawKind",
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
  expect({ exitCode, stdout, stderr }).toEqual({ exitCode: 0, stdout: "", stderr: "" });
  return fs.readFileSync(path.join(output, target.file), "utf8");
}

test("@:sealed on a class reports the interface-only error", async () => {
  const mutationRoot = fs.mkdtempSync(path.join(root, ".sealed-variants-mutation-"));
  try {
    const sourceRoot = path.join(mutationRoot, "samples");
    const sourceFile = path.join(sourceRoot, "boring/InvalidSealed.hx");
    const hxml = path.join(mutationRoot, "invalid-sealed.hxml");
    fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
    fs.writeFileSync(sourceFile, [
      "package boring;",
      "",
      "@:sealed",
      "class InvalidSealed {}",
      "",
    ].join("\n"));
    fs.writeFileSync(hxml, [
      "-lib reflaxe",
      "-lib boring",
      `-cp ${path.join(root, "src/reflaxe/ts/std-shadow")}`,
      `-cp ${path.join(root, "src/reflaxe/ts")}`,
      `-cp ${path.join(root, "samples")}`,
      `-cp ${sourceRoot}`,
      `--macro Intercept.run(["${sourceRoot}"])`,
      "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
      "--macro tscompiler.Compiler.use()",
      `-D ts-output=${path.join(mutationRoot, "ts")}`,
      "boring.InvalidSealed",
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
    expect(stdout + stderr).toContain("@:sealed applies to interfaces only");
  } finally {
    fs.rmSync(mutationRoot, { recursive: true, force: true });
  }
});

test("self-construction with arguments keeps the static initializer error", async () => {
  const mutationRoot = fs.mkdtempSync(path.join(root, ".sealed-variants-static-mutation-"));
  try {
    const sourceRoot = path.join(mutationRoot, "samples");
    const sourceFile = path.join(sourceRoot, "boring/InvalidSelfConstruction.hx");
    const hxml = path.join(mutationRoot, "invalid-self-construction.hxml");
    fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
    fs.writeFileSync(sourceFile, [
      "package boring;",
      "",
      "class NoneDrawKind {",
      "  public static final bad:NoneDrawKind = new NoneDrawKind(1);",
      "  private function new(?marker:Int) {}",
      "}",
      "",
    ].join("\n"));
    fs.writeFileSync(hxml, [
      "-lib reflaxe",
      "-lib boring",
      `-cp ${path.join(root, "src/reflaxe/ts/std-shadow")}`,
      `-cp ${path.join(root, "src/reflaxe/ts")}`,
      `-cp ${path.join(root, "samples")}`,
      `-cp ${sourceRoot}`,
      `--macro Intercept.run(["${sourceRoot}"])`,
      "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
      "--macro tscompiler.Compiler.use()",
      `-D ts-output=${path.join(mutationRoot, "ts")}`,
      "boring.InvalidSelfConstruction",
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
    expect(stdout + stderr).toContain("static field initializers accept null, literal, and empty array forms only");
  } finally {
    fs.rmSync(mutationRoot, { recursive: true, force: true });
  }
});

test("the sanctioned self-construction static uses each target lane", async () => {
  const mutationRoot = fs.mkdtempSync(path.join(root, ".sealed-variants-static-shapes-"));
  try {
    const sourceRoot = path.join(mutationRoot, "samples");
    const trees: Record<string, string> = {};
    for(const target of selfTargets) {
      trees[target.id] = await generateSelfConstruction(mutationRoot, sourceRoot, target);
    }
    expect(trees.ts).toContain("public static readonly instance: NoneDrawKind = new NoneDrawKind();");
    expect(trees.kotlin).toContain("val instance: NoneDrawKind = NoneDrawKind()");
    expect(trees.swift).toContain("static let instance: NoneDrawKind = NoneDrawKind()");
    expect(trees.dart).toContain("static final instance = NoneDrawKind();");
    expect(trees.rust).not.toContain("#[allow(non_upper_case_globals)]");
    expect(trees.rust).toContain("pub static INSTANCE: Mutex<NoneDrawKind> = Mutex::new(NoneDrawKind::new());");;
  } finally {
    fs.rmSync(mutationRoot, { recursive: true, force: true });
  }
});

test("sealed variant sample trees carry the ruled declaration and printed forms", () => {
  const read = (file: string): string => fs.readFileSync(path.join(root, file), "utf8");
  const ts = read("reference/ts/gen/boring/SealedVariantOps.ts");
  const kotlin = read("reference/kotlin/gen/boring/SealedVariantOps.kt");
  const swift = read("reference/swift/gen/boring/SealedVariantOps.swift");
  const dart = read("reference/dart/gen/lib/boring/sealed_variant_ops.dart");
  const rust = read("reference/rust-gen/src/boring/sealed_variant_ops.rs");

  expect(kotlin).toContain("sealed interface DrawKind");
  expect(kotlin).toContain("val instance: NoneDrawKind = NoneDrawKind()");
  expect(kotlin).toContain("data class StripeDrawKind(val strokeWidth: Double, val gapLength: Double) : DrawKind");
  expect(kotlin).toContain("data class DotDrawKind(val dotDiameter: Double, val gapLength: Double) : DrawKind");

  expect(ts).toContain("public static readonly instance: NoneDrawKind = new NoneDrawKind();");
  expect(ts).toContain('return "NoneDrawKind";');
  expect(ts).toContain("StripeDrawKind(strokeWidth=");
  expect(ts).toContain("DotDrawKind(dotDiameter=");

  expect(swift).toContain("static let instance: NoneDrawKind = NoneDrawKind()");
  expect(swift).toContain('return "NoneDrawKind"');
  expect(swift).toContain("StripeDrawKind(strokeWidth=");
  expect(swift).toContain("DotDrawKind(dotDiameter=");

  expect(dart).toContain("abstract class DrawKind");
  expect(dart).toContain("static final instance = NoneDrawKind();");
  expect(dart).toContain('return "NoneDrawKind";');
  expect(dart).toContain("StripeDrawKind(strokeWidth=");
  expect(dart).toContain("DotDrawKind(dotDiameter=");

  expect(rust).not.toContain("#[allow(non_upper_case_globals)]");
  expect(rust).toContain("pub static INSTANCE: Mutex<NoneDrawKind> = Mutex::new(NoneDrawKind::new());");;
  expect(rust).toContain('return "NoneDrawKind".to_string();');
  expect(rust).toContain('"StripeDrawKind("');
  expect(rust).toContain('"DotDrawKind("');
});
