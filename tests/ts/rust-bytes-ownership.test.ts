import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "../..");

test("Rust borrows input Bytes fields and owns allocated Bytes fields", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "rust-bytes-ownership-"));
  const sourceRoot = path.join(dir, "src");
  const output = path.join(dir, "out");
  fs.mkdirSync(path.join(sourceRoot, "fixture"), { recursive: true });
  fs.writeFileSync(path.join(sourceRoot, "fixture/Borrowed.hx"), [
    "package fixture;", "import haxe.io.Bytes;",
    "class Borrowed { final bytes:Bytes; public function new(bytes:Bytes) this.bytes = bytes; }", "",
  ].join("\n"));
  fs.writeFileSync(path.join(sourceRoot, "fixture/Owned.hx"), [
    "package fixture;", "import haxe.io.Bytes;",
    "class Owned { var bytes:Bytes; public function new() bytes = Bytes.alloc(64); }", "",
  ].join("\n"));
  fs.writeFileSync(path.join(sourceRoot, "fixture/Probe.hx"), [
    "package fixture;", "class Probe { public static function make():Owned return new Owned(); }", "",
  ].join("\n"));
  const hxml = path.join(dir, "probe.hxml");
  fs.writeFileSync(hxml, [
    "-lib reflaxe", "-lib boring",
    `-cp ${path.join(root, "src/reflaxe/rust/std-shadow")}`,
    `-cp ${path.join(root, "src/reflaxe/rust")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    "--macro rustcompiler.Compiler.use()",
    `-D rust-output=${output}`,
    "-D package-shell=none",
    "fixture.Probe", "fixture.Borrowed", "fixture.Owned", "",
  ].join("\n"));
  try {
    const proc = Bun.spawn(["haxe", hxml], { cwd: root, stdout: "pipe", stderr: "pipe" });
    const [code, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect({ code, stderr }).toEqual({ code: 0, stderr: "" });
    expect(fs.readFileSync(path.join(output, "fixture/borrowed.rs"), "utf8")).toContain("bytes: &'a [u8]");
    expect(fs.readFileSync(path.join(output, "fixture/owned.rs"), "utf8")).toContain("bytes: Vec<u8>");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
