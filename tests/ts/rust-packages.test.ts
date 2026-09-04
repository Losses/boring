import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "../..");

test("Rust emits one module layer per Haxe package segment", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "rust-nested-package-"));
  const sourceRoot = path.join(dir, "src");
  const output = path.join(dir, "out");
  fs.mkdirSync(path.join(sourceRoot, "outer/inner"), { recursive: true });
  fs.writeFileSync(path.join(sourceRoot, "outer/inner/Probe.hx"), [
    "package outer.inner;",
    "class Probe { public static function value():Int return 7; }",
    "",
  ].join("\n"));
  const hxml = path.join(dir, "probe.hxml");
  fs.writeFileSync(hxml, [
    "-lib reflaxe", "-lib boring",
    `-cp ${path.join(root, "packages/compiler/reflaxe/rust/std-shadow")}`,
    `-cp ${path.join(root, "packages/compiler/reflaxe/rust")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    "--macro rustcompiler.Compiler.use()",
    `-D rust-output=${output}`,
    "-D package-shell=none",
    "outer.inner.Probe", "",
  ].join("\n"));
  try {
    const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
    const [code, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect({ code, stderr }).toEqual({ code: 0, stderr: "" });
    expect(fs.readFileSync(path.join(output, "lib.rs"), "utf8")).toContain("pub mod outer;");
    expect(fs.readFileSync(path.join(output, "outer/mod.rs"), "utf8")).toContain("pub mod inner;");
    expect(fs.readFileSync(path.join(output, "outer/inner/mod.rs"), "utf8")).toContain("pub mod probe;");
    expect(fs.existsSync(path.join(output, "outer/inner/probe.rs"))).toBe(true);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
