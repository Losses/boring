import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "../..");

function read(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

test("deferred locals retain each target's sanctioned declaration form", () => {
  expect(read("reference/ts/gen/boring/DeferredLocalsOps.ts")).toContain("let tier: number;");
  expect(read("reference/kotlin/gen/boring/DeferredLocalsOps.kt")).toContain("var tier: Int");
  expect(read("reference/swift/gen/boring/DeferredLocalsOps.swift")).toContain("var tier: Int32");
  expect(read("reference/dart/gen/lib/boring/deferred_locals_ops.dart")).toContain("int tier;");
  expect(read("reference/rust-gen/src/boring/deferred_locals_ops.rs")).toContain("let mut tier: u32;");
});

test("a missing deferred assignment is rejected by the Kotlin tree build", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "boring-deferred-locals-mutation-"));
  try {
    const sourceRoot = path.join(dir, "samples");
    const sourceFile = path.join(sourceRoot, "boring/InvalidDeferredLocals.hx");
    const output = path.join(dir, "kotlin");
    fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
    fs.writeFileSync(sourceFile, [
      "package boring;",
      "class InvalidDeferredLocals {",
      "  public static function tierOf(value:Int):Int {",
      "    var tier:Int;",
      "    if (value > 2) tier = 2; else tier = value;",
      "    return tier;",

      "  }",
      "}",
      "",
    ].join("\n"));
    const hxml = path.join(dir, "invalid.hxml");
    fs.writeFileSync(hxml, [
      "-lib reflaxe", "-lib boring",
      `-cp ${path.join(root, "src/reflaxe/kotlin/std-shadow")}`,
      `-cp ${path.join(root, "src/reflaxe/kotlin")}`,
      `-cp ${path.join(root, "samples")}`, `-cp ${sourceRoot}`,
      `--macro Intercept.run(["${sourceRoot}"])`,
      "--macro kotlincompiler.Compiler.use()",
      `-D kotlin-output=${output}`,
      "boring.InvalidDeferredLocals", "",
    ].join("\n"));

    const generated = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
    const [haxeCode, haxeOut, haxeErr] = await Promise.all([
      generated.exited, new Response(generated.stdout).text(), new Response(generated.stderr).text(),
    ]);
    expect({ haxeCode, haxeOut, haxeErr }).toEqual({ haxeCode: 0, haxeOut: "", haxeErr: "" });

    const kotlinFile = path.join(output, "boring/InvalidDeferredLocals.kt");
    fs.writeFileSync(kotlinFile, fs.readFileSync(kotlinFile, "utf8").replace("tier = value", "/* deleted assignment */"));
    const kotlin = Bun.spawn(["kotlinc", kotlinFile, "-d", path.join(dir, "invalid.jar")], {
      cwd: root, stdout: "pipe", stderr: "pipe",
    });
    const [code, stdout, stderr] = await Promise.all([
      kotlin.exited, new Response(kotlin.stdout).text(), new Response(kotlin.stderr).text(),
    ]);
    expect(code).not.toBe(0);
    expect(stdout + stderr).toMatch(/(must be initialized|variable 'tier' must be initialized)/i);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
