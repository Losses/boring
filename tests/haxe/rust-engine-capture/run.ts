import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

// bun run script (not bun test): the acceptance ladder wants a process with a
// deterministic exit code, with no framework teardown in the path.
// Assertion failure -> console.error + exit(1); all pass -> exit(0).

const REPO_ROOT = resolve(import.meta.dir, "..", "..", "..");
const CHECK = join(import.meta.dir, "check.sh");
const HXML = join(import.meta.dir, "gen/rust.hxml");

function have(cmd: string): boolean {
  return spawnSync("which", [cmd], { encoding: "utf8" }).status === 0;
}
function fail(msg: string): never {
  console.error("FAIL: " + msg);
  process.exit(1);
}

if (!have("haxe")) fail("haxe not on PATH; cannot generate the fixture");
if (!have("cargo")) fail("cargo not on PATH; cannot build the fixture");

const t0 = performance.now();
// generation goes to a one-shot temp dir, never into the repo tree, so a
// later run cannot read a stale product.
const gen = mkdtempSync(join(tmpdir(), "rust-engine-capture-"));
try {
  const genProc = spawnSync("haxe", ["-D", "rust-output=" + gen, HXML], { cwd: REPO_ROOT, encoding: "utf8", timeout: 120000 });
  if (genProc.status !== 0) fail("haxe generation failed (status=" + genProc.status + "): " + genProc.stdout + genProc.stderr);

  // assertion: engine.rs was emitted, surviving dead-code elimination.
  const engineRs = join(gen, "probe/engine.rs");
  if (!existsSync(engineRs)) fail("engine.rs missing (path was dead-code-eliminated)");

  // single implementation point: all ABI-shape assertions (signature / no bare
  // borrow) live in check.sh; this script only runs it and checks the exit code.
  const check = spawnSync("bash", [CHECK, gen], { encoding: "utf8", timeout: 30000 });
  if (check.status !== 0) fail("check.sh failed:\n" + check.stdout + check.stderr);
  console.log(check.stdout.trim());

  // assertion: the generated crate compiles.
  const build = spawnSync("cargo", ["build"], { cwd: gen, encoding: "utf8", timeout: 120000 });
  if (build.status !== 0) fail("cargo build failed:\n" + build.stdout + build.stderr);
} finally {
  rmSync(gen, { recursive: true, force: true });
}
console.log("rust-engine-capture fixture: " + (performance.now() - t0).toFixed(0) + "ms");
process.exit(0);
