import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "../..");

async function compileFixture(source: string): Promise<{ code: number; output: string; dir: string }> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ts-extern-bindings-"));
  const sourceRoot = path.join(dir, "src");
  fs.mkdirSync(path.join(sourceRoot, "fixtures"), { recursive: true });
  fs.writeFileSync(path.join(sourceRoot, "fixtures/Externs.hx"), [
    "package fixtures;",
    '@:jsRequire("pkg") extern class Namespace { public static function value():Int; }',
    '@:jsRequire("pkg", "named") extern class Named { public static function value():Int; }',
    '@:native("globalThing") extern class GlobalThing { public static function value():Int; }',
    "extern class Empty { public static function value():Int; }",
    "",
  ].join("\n"));
  fs.writeFileSync(path.join(sourceRoot, "fixtures/Probe.hx"), source);
  const hxml = path.join(dir, "probe.hxml");
  fs.writeFileSync(hxml, [
    "-lib reflaxe", "-lib boring",
    `-cp ${path.join(root, "src/reflaxe/ts")}`,
    `-cp ${path.join(root, "src/reflaxe/ts/std-shadow")}`,
    `-cp ${path.join(root, "samples")}`, `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"], [])`,
    "--macro tscompiler.Compiler.use()", `-D ts-output=${path.join(dir, "out")}`,
    "fixtures.Probe", "",
  ].join("\n"));
  const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
  const [code, out, err] = await Promise.all([proc.exited, new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  return { code, output: out + err, dir };
}

describe("TypeScript extern binding modules", () => {
  test("emits jsRequire namespace/named and native global bindings once", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "import fixtures.Externs.GlobalThing;",
      "import fixtures.Externs.Named;",
      "import fixtures.Externs.Namespace;",
      "class Probe {",
      "  public static function read():Int return Namespace.value() + Named.value() + GlobalThing.value() + Namespace.value();",
      "}", "",
    ].join("\n"));
    try {
      expect(result.code).toBe(0);
      const bindings = fs.readFileSync(path.join(result.dir, "out/fixtures/Externs.ts"), "utf8");
      expect(bindings).toContain('import * as ns_Namespace from "pkg";');
      expect(bindings).toContain("export const Namespace = ns_Namespace;");
      expect(bindings).toContain('import { named } from "pkg";');
      expect(bindings).toContain("export const Named = named;");
      expect(bindings).toContain("export const globalThing = globalThis.globalThing;");
      expect(bindings.match(/export const Namespace =/g)?.length).toBe(1);
      const probe = fs.readFileSync(path.join(result.dir, "out/fixtures/Probe.ts"), "utf8");
      expect(probe).toContain('import { Named, Namespace, globalThing } from "./Externs.ts";');
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });

  test("rejects a value reference to an empty module", async () => {
    const result = await compileFixture([
      "package fixtures;",
      "import fixtures.Externs.Empty;",
      "class Probe { public static function read():Int return Empty.value(); }", "",
    ].join("\n"));
    try {
      expect(result.code).not.toBe(0);
      expect(result.output).toContain("extern class Empty carries no @:native and no @:jsRequire");
    } finally {
      fs.rmSync(result.dir, { recursive: true, force: true });
    }
  });
});
