import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
const REPO_ROOT = "/home/losses/Development/tq-workspace/boring-wt-architecture";
const TSC = path.join(REPO_ROOT, "node_modules/typescript/bin/tsc");
const N = Number(process.argv[2] ?? 5);
const tag = process.argv[3] ?? "run";

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

function runHaxe(hxmlName, content) {
  const hxmlPath = path.join(REPO_ROOT, "out", hxmlName);
  fs.mkdirSync(path.dirname(hxmlPath), { recursive: true });
  fs.writeFileSync(hxmlPath, content);
  const probe = path.join(REPO_ROOT, "samples/boring/MathNaNTestSupport.hx");
  const isTs = content.includes("ts-output") || hxmlName.includes("npm") || hxmlName.includes("tsc") || hxmlName.includes("id-");
  let hidden = false, backup = "";
  const stub = "package boring;\nclass MathNaNTestSupport {\n    public static function assertNaN(value:Float, message:String):Void {}\n    public static function assertNegativeZero(value:Float, message:String):Void {}\n    public static function assertPositiveZero(value:Float, message:String):Void {}\n}\n";
  if (isTs && fs.existsSync(probe)) { backup = fs.readFileSync(probe, "utf8"); fs.writeFileSync(probe, stub); hidden = true; }
  try {
    const proc = Bun.spawnSync(["haxe", path.relative(REPO_ROOT, hxmlPath)], { cwd: REPO_ROOT });
    return { exitCode: proc.exitCode, stderr: proc.stderr.toString() };
  } finally {
    if (hidden) fs.writeFileSync(probe, backup);
  }
}

const root = `/tmp/npm-det-${tag}`;
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(root, { recursive: true });
const results = [];
for (let i = 0; i < N; i++) {
  const a = runHaxe(`package-artifacts-det-${i}.hxml`, rewriteHxml("ts.hxml", root, [`-D package-tsc=${TSC}`]));
  if (a.exitCode !== 0 || a.stderr !== "") { console.log(`gen${i}: COMPILE FAIL exit=${a.exitCode}`); console.log(a.stderr.slice(0, 2000)); continue; }
  const tgz = path.join(root, "ts/generated-0.1.0.tgz");
  const buf = fs.readFileSync(tgz);
  const sha = crypto.createHash("sha256").update(buf).digest("hex");
  const lst = Bun.spawnSync(["tar", "tzf", tgz]);
  const names = lst.stdout.toString().trim().split("\n");
  const has = names.filter(n => n.includes("MathNaNTestSupport"));
  results.push({ i, sha, count: names.length, has });
  console.log(`gen${i}: entries=${names.length} sha256=${sha} nanEntries=${JSON.stringify(has)}`);
}
const unique = new Set(results.map(r => r.sha));
console.log(`unique hashes across ${results.length} generations: ${unique.size}`);
