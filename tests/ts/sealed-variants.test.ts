import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

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
      `--macro Intercept.run(["${sourceRoot}"], [])`,
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
