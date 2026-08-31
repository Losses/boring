import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");
const read = (file: string): string => fs.readFileSync(path.join(root, file), "utf8");

describe("constructed static initializer trees", () => {
  test("each target uses its ruled declaration and Rust read lane", () => {
    expect(read("reference/ts/gen/boring/ConstructedStateOps.ts")).toContain(
      "public static readonly weighted: FramePolicy = new FramePolicy("
    );
    expect(read("reference/kotlin/gen/boring/ConstructedStateOps.kt")).toContain(
      "val weighted: FramePolicy = FramePolicy("
    );
    expect(read("reference/swift/gen/boring/ConstructedStateOps.swift")).toContain(
      "static let weighted: FramePolicy = FramePolicy("
    );
    expect(read("reference/dart/gen/lib/boring/constructed_state_ops.dart")).toContain(
      "static final FramePolicy weighted = FramePolicy("
    );
    const rust = read("reference/rust-gen/src/boring/constructed_state_ops.rs");
    expect(rust).toContain("LazyLock<FramePolicy>");
    expect(rust).toContain("LazyLock::new");
    expect(rust).toContain("#[allow(non_upper_case_globals)]");
    expect(rust).toContain("&*weighted");
  });
});

async function compileMutation(source: string): Promise<string> {
  const dir = fs.mkdtempSync(path.join(root, ".constructed-static-mutation-"));
  try {
    const sourceRoot = path.join(dir, "samples");
    fs.mkdirSync(path.join(sourceRoot, "boring"), { recursive: true });
    fs.writeFileSync(path.join(sourceRoot, "boring/Probe.hx"), source);
    const hxml = path.join(dir, "probe.hxml");
    fs.writeFileSync(hxml, [
      "-lib reflaxe", "-lib boring",
      `-cp ${path.join(root, "src/reflaxe/ts/std-shadow")}`,
      `-cp ${path.join(root, "src/reflaxe/ts")}`,
      `-cp ${path.join(root, "samples")}`, `-cp ${sourceRoot}`,
      `--macro Intercept.run(["${sourceRoot}"], [])`,
      "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
      "--macro tscompiler.Compiler.use()", `-D ts-output=${path.join(dir, "out")}`,
      "boring.Probe", "",
    ].join("\n"));
    const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
    const [code, out, err] = await Promise.all([proc.exited, new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
    expect(code).not.toBe(0);
    return out + err;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("constructed static mutation rules retain all three diagnostics", async () => {
  const varError = await compileMutation([
    "package boring;", "class Probe {", "  public static var bad:Probe = new Probe();", "  public function new() {}", "}", "",
  ].join("\n"));
  expect(varError).toContain("static field initializers accept null, literal, and empty array forms only");

  const finalError = await compileMutation([
    "package boring;", "class Probe {", "  public static final bad:Int = make();", "  public static function make():Int return 1;", "}", "",
  ].join("\n"));
  expect(finalError).toContain("static field initializers accept null, literal, empty array, and construction forms only");

  const argumentError = await compileMutation([
    "package boring;", "class Probe {", "  public static final bad:Probe = new Probe((function() { var local = 1; return local; })());", "  public function new(value:Int) {}", "}", "",
  ].join("\n"));
  expect(argumentError).toContain("constructed static field arguments accept literal, enum, array, construction, static field, and static function forms only");
});
