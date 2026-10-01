import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
const REPO_ROOT = "/home/losses/Development/tq-workspace/boring-wt-architecture";
const TSC = path.join(REPO_ROOT, "node_modules/typescript/bin/tsc");
// Variants: "stub" = replicate test harness (stubs fixture), "real" = no stub.
const mode = process.argv[2];
const N = Number(process.argv[3] ?? 3);
const tag = process.argv[4] ?? mode;

function rewriteHxml(name, root, extra = []) {
  const source = fs.readFileSync(path.join(REPO_ROOT, "examples", name), "utf8");
  let out = source.replace(/reference\/[a-z0-9-]+(\/[a-z0-9-]+)*/g, (m) => m.replace("reference", root));
  out = out.replace("-D runtime-import=@boring/runtime", "-D runtime-import=./runtime");
  out = out.replace("-D package-shell=none\n", "");
  out = out.replaceAll("boring.MathNaNTestSupport\n", "");
  out += "-D package-artifacts=emit\n";
  for (const line of extra) out += line + "\n";
  return out;
}
const stub = "package boring;\nclass MathNaNTestSupport {\n    public static function assertNaN(value:Float, message:String):Void {}\n    public static function assertNegativeZero(value:Float, message:String):Void {}\n    public static function assertPositiveZero(value:Float, message:String):Void {}\n}\n";
function runHaxe(hxmlName, content) {
  const hxmlPath = path.join(REPO_ROOT, "out", hxmlName);
  fs.mkdirSync(path.dirname(hxmlPath), { recursive: true });
  fs.writeFileSync(hxmlPath, content);
  const probe = path.join(REPO_ROOT, "samples/boring/MathNaNTestSupport.hx");
  let hidden = false, backup = "";
  if (mode === "stub") { backup = fs.readFileSync(probe, "utf8"); fs.writeFileSync(probe, stub); hidden = true; }
  try {
    const p = Bun.spawnSync(["haxe", path.relative(REPO_ROOT, hxmlPath)], { cwd: REPO_ROOT });
    return { exitCode: p.exitCode, stderr: p.stderr.toString() };
  } finally { if (hidden) fs.writeFileSync(probe, backup); }
}
const root = `/tmp/npm-det2-${tag}`;
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(root, { recursive: true });
const hashes = new Set();
for (let i = 0; i < N; i++) {
  const a = runHaxe(`package-artifacts-${tag}-${i}.hxml`, rewriteHxml("ts.hxml", root, [`-D package-tsc=${TSC}`]));
  if (a.exitCode !== 0) { console.log(`gen${i}: FAIL ${a.stderr.slice(0,800)}`); continue; }
  const tgz = path.join(root, "ts/generated-0.1.0.tgz");
  const buf = fs.readFileSync(tgz);
  const sha = crypto.createHash("sha256").update(buf).digest("hex");
  hashes.add(sha);
  const names = Bun.spawnSync(["tar","tzf",tgz]).stdout.toString().trim().split("\n");
  console.log(`${mode} gen${i}: entries=${names.length} sha256=${sha} nan=${JSON.stringify(names.filter(n=>n.includes("MathNaNTestSupport")))}`);
}
console.log(`${mode}: unique hashes = ${hashes.size}`);
