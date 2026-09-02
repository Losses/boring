import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "../..");

type CompileResult = { code: number; output: string; dir: string };

async function compileFixture(source: string): Promise<CompileResult> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ts-strict-output-"));
  const sourceRoot = path.join(dir, "src");
  fs.mkdirSync(path.join(sourceRoot, "fixtures"), { recursive: true });
  fs.writeFileSync(path.join(sourceRoot, "fixtures/Probe.hx"), source);
  const hxml = path.join(dir, "probe.hxml");
  fs.writeFileSync(hxml, [
    "-lib reflaxe", "-lib boring",
    `-cp ${path.join(root, "src/reflaxe/ts")}`,
    `-cp ${path.join(root, "src/reflaxe/ts/std-shadow")}`,
    `-cp ${path.join(root, "samples")}`, `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    "--macro tscompiler.Compiler.use()", `-D ts-output=${path.join(dir, "out")}`,
    "fixtures.Probe", "",
  ].join("\n"));
  const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
  const [code, out, err] = await Promise.all([proc.exited, new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  return { code, output: out + err, dir };
}

describe("strict TypeScript emitter output", () => {
  test("omitted indexOf positions drop synthesized null for strings and arrays", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "class Probe {",
      "  public static function run(text:String, values:Array<Int>):Int return text.indexOf(\"x\") + values.indexOf(2);",
      "}", "",
    ].join("\n"));
    try {
      expect(result.code).toBe(0);
      const output = fs.readFileSync(path.join(result.dir, "out/fixtures/Probe.ts"), "utf8");
      expect(output).toContain('.indexOf("x")');
      expect(output).toContain("values.indexOf(2)");
      expect(output).not.toContain("indexOf(\"x\", null)");
      expect(output).not.toContain("indexOf(2, null)");
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });

  test("single-argument substr drops its synthesized null length", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "class Probe { public static function run(text:String):String return text.substr(1); }", "",
    ].join("\n"));
    try {
      expect(result.code).toBe(0);
      const output = fs.readFileSync(path.join(result.dir, "out/fixtures/Probe.ts"), "utf8");
      expect(output).toContain("text.substr(1)");
      expect(output).not.toContain("text.substr(1, null)");
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });

  test("switch-expression cases render preceding statements before their value", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "enum Choice { First; Other; }",
      "class Probe {",
      "  public static function run(value:Choice):Int return switch (value) {",
      "    case First: { var next = 1; next; }",
      "    case Other: 2;",
      "  };",
      "}", "",
    ].join("\n"));
    try {
      expect(result.code).toBe(0);
      const output = fs.readFileSync(path.join(result.dir, "out/fixtures/Probe.ts"), "utf8");
      expect(output).toContain('case "First":');
      expect(output).toMatch(/const next = 1;[\s\S]*return next;/);
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });

  test("adjacent source blocks preserve lexical scope", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "class Probe {",
      "  public static function run():Int {",
      "    var result = 0;",
      "    { final value = 1; result += value; }",
      "    { final value = 2; result += value; }",
      "    return result;",
      "  }",
      "}", "",
    ].join("\n"));
    try {
      expect(result.code).toBe(0);
      const output = fs.readFileSync(path.join(result.dir, "out/fixtures/Probe.ts"), "utf8");
      expect(output).toContain("const value = 1;");
      expect(output).toContain("const value2 = 2;");
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });

  test("empty-array and null local initializers retain declared TypeScript types", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "class Probe {",
      "  public static function run(seed:Int):Int {",
      "    var values:Array<Int> = [];",
      "    var name:Null<String> = null;",
      "    values.push(seed);",
      "    return values.length + (name == null ? 0 : name.length);",
      "  }",
      "}", "",
    ].join("\n"));
    try {
      expect(result.code).toBe(0);
      const output = fs.readFileSync(path.join(result.dir, "out/fixtures/Probe.ts"), "utf8");
      expect(output).toContain("const values: number[] = [];");
      expect(output).toContain("const name: string | null = null;");
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });
});
