import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");
const read = (file: string): string => fs.readFileSync(path.join(root, file), "utf8");

describe("small static array initializer trees", () => {
  test("each target uses the ruled array declaration", () => {
    expect(read("reference/ts/gen/boring/ArrayRootStateOps.ts")).toContain(
      "public static readonly readOnlyInts: readonly number[] = [10, 20, 30];",
    );

    const kotlin = read("reference/kotlin/gen/boring/ArrayRootStateOps.kt");
    expect(kotlin).toContain("val readOnlyInts: List<Int> = listOf(10, 20, 30)");
    expect(kotlin).toContain("val mutableInts: MutableList<Int> = mutableListOf<Int>(40, 50)");

    expect(read("reference/swift/gen/boring/ArrayRootStateOps.swift")).toContain(
      "static let readOnlyInts: [Int32] = [10, 20, 30]",
    );
    expect(read("reference/dart/gen/lib/boring/array_root_state_ops.dart")).toContain(
      "static final List<int> readOnlyInts = [10, 20, 30];",
    );

    const rust = read("reference/rust-gen/src/boring/array_root_state_ops.rs");
    expect(rust).toMatch(/pub static READ_ONLY_INTS: \[(?:u32|i32); 3\] = \[10, 20, 30\];/);
    expect(rust).toContain("pub static MUTABLE_INTS: [u32; 2] = [40, 50];");
    expect(rust).toContain("LazyLock<Vec<String>>");
    expect(rust).toContain("LazyLock<Vec<ArrayRootKind>>");
    expect(rust).toContain("LazyLock::new");
  });
});

async function compileMutation(source: string): Promise<string> {
  const dir = fs.mkdtempSync(path.join(root, ".array-root-mutation-"));
  try {
    const sourceRoot = path.join(dir, "samples");
    fs.mkdirSync(path.join(sourceRoot, "boring"), { recursive: true });
    fs.writeFileSync(path.join(sourceRoot, "boring/Probe.hx"), source);
    const hxml = path.join(dir, "probe.hxml");
    fs.writeFileSync(hxml, [
      "-lib reflaxe", "-lib boring",
      `-cp ${path.join(root, "packages/compiler/reflaxe/ts/std-shadow")}`,
      `-cp ${path.join(root, "packages/compiler/reflaxe/ts")}`,
      `-cp ${path.join(root, "samples")}`, `-cp ${sourceRoot}`,
      `--macro Intercept.run(["${sourceRoot}"])`,
      "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
      "--macro tscompiler.Compiler.use()", `-D ts-output=${path.join(dir, "out")}`,
      "boring.Probe", "",
    ].join("\n"));
    const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
    const [code, stdout, stderr] = await Promise.all([
      proc.exited,
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    expect(code).not.toBe(0);
    return stdout + stderr;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("small array initializer mutation rules retain all three diagnostics", async () => {
  const varError = await compileMutation([
    "package boring;",
    "class Probe {",
    "  public static var bad:Array<Int> = [1, 2];",
    "}",
    "",
  ].join("\n"));
  expect(varError).toContain("static field initializers accept null, literal, and empty array forms only");

  const elementError = await compileMutation([
    "package boring;",
    "class Probe {",
    "  public static final bad:Array<Int> = [(function() { var local = 1; return local; })()];",
    "}",
    "",
  ].join("\n"));
  expect(elementError).toContain("constructed static field arguments accept literal, enum, array, construction, static field, and static function forms only");

  const rootError = await compileMutation([
    "package boring;",
    "class Probe {",
    "  public static final bad:Int = make();",
    "  public static function make():Int return 1;",
    "}",
    "",
  ].join("\n"));
  expect(rootError).toContain("static field initializers accept null, literal, array, and construction forms only");
});
