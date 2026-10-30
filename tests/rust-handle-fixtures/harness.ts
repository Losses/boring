import { readdirSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { spawnSync } from "node:child_process";

const REPO_ROOT = dirname(dirname(import.meta.dir));
const FIXTURE_DIR = join(REPO_ROOT, "samples", "rusthandlefixtures");
const OUT_ROOT = join(REPO_ROOT, "out", "rust-handle-fixtures");

const CONSTRUCTS: Record<string, string> = {
  SelfRewrap: "self-receiver",
  NewReceiver: "new-receiver",
  OwnedParam: "owned-param",
  BorrowedParam: "borrowed-param",
  HandleFieldRead: "field-read",
  HandleFieldWrite: "field-write",
  ChainedCall: "chained-call",
  ReturnHandle: "return-handle",
  NullableHandle: "nullable",
  ClosureCapture: "closure",
  InterfaceDispatch: "interface-dispatch",
  StaticMutable: "static-mutable",
  CollectionHandle: "collection",
  AliasIdentity: "alias-identity",
};

const GOLDEN_PATTERNS: Array<{ category: string; pattern: RegExp; desc: string }> = [
  { category: "SELF_REWRAP", pattern: /Rc::new\s*\(\s*RefCell::new\s*\(\s*self\b/, desc: "Rc::new(RefCell::new(self.clone()))" },
  { category: "SEND_SYNC", pattern: /Send\s*\+\s*Sync/, desc: "Send + Sync trait bound" },
  { category: "MUT_SELF", pattern: /&\s*mut\s+self\b/, desc: "&mut self receiver" },
];

function fixtureNames(): string[] {
  return readdirSync(FIXTURE_DIR).filter((f) => f.endsWith(".hx")).map((f) => f.replace(/\.hx$/, "")).sort();
}

function hxmlFor(name: string, genDir: string): string {
  const lines = [
    "-lib reflaxe",
    "-lib boring",
    "-cp packages/compiler/reflaxe/rust/std-shadow",
    "-cp packages/compiler/reflaxe/rust",
    "-cp samples",
    "-cp samples/haxe",
    "-cp packages/registry/src",
    "-cp packages/driver/src",
    "--macro Intercept.run(['samples', 'packages/registry/src', 'packages/driver/src'])",
    "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    "--macro rustcompiler.Compiler.use()",
    "-D rust-output=" + genDir,
    "-D runtime-import=crate::runtime",
    "-D runtime-emit=runtime",
    "-D package-name=rusthandlefixtures-" + name.toLowerCase(),
    "-D package-license=MIT",
    "rusthandlefixtures." + name,
  ];
  return lines.join("\n") + "\n";
}

function allGeneratedRs(genDir: string): string {
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".rs")) out.push(readFileSync(p, "utf8"));
    }
  };
  walk(join(genDir, "rusthandlefixtures"));
  return out.join("\n");
}

function parseCargoErrors(stderr: string): Array<{ code: string; rule: string }> {
  const res: Array<{ code: string; rule: string }> = [];
  for (const m of stderr.matchAll(/error\[(E\d+)\]:\s*([^\n]*)/g)) {
    res.push({ code: m[1], rule: m[2].trim() });
  }
  return res;
}

function runFixture(name: string): any {
  const genDir = join(OUT_ROOT, name.toLowerCase() + "-gen");
  rmSync(genDir, { recursive: true, force: true });
  mkdirSync(genDir, { recursive: true });
  const hxmlPath = join(OUT_ROOT, name.toLowerCase() + ".hxml");
  writeFileSync(hxmlPath, hxmlFor(name, genDir));

  const gen = spawnSync("haxe", [hxmlPath], { cwd: REPO_ROOT, encoding: "utf8" });
  if (gen.status !== 0) {
    return {
      fixture: name,
      construct: CONSTRUCTS[name] ?? "unknown",
      compile: "gen-error",
      cargoErrors: [],
      fingerprints: ["GEN_ERROR|haxe-exit-" + gen.status + "|" + name],
      genStderr: gen.stderr.trim().slice(0, 400),
    };
  }

  const rustText = allGeneratedRs(genDir);
  const fingerprints: string[] = [];
  for (const g of GOLDEN_PATTERNS) {
    if (g.pattern.test(rustText)) fingerprints.push(g.category + "|" + g.desc + "|" + name);
  }

  const manifest = join(genDir, "Cargo.toml");
  if (!readFileSync(manifest, "utf8").includes("[workspace]")) {
    writeFileSync(manifest, readFileSync(manifest, "utf8") + "\n[workspace]\n");
  }
  const check = spawnSync("cargo", ["check", "--manifest-path", manifest], { cwd: REPO_ROOT, encoding: "utf8" });
  const cargoErrors = check.status === 0 ? [] : parseCargoErrors(check.stderr);
  for (const e of cargoErrors) fingerprints.push(e.code + "|" + e.rule + "|" + name);
  if (cargoErrors.length === 0 && fingerprints.length === 0) fingerprints.push("OK|-|" + name);

  return {
    fixture: name,
    construct: CONSTRUCTS[name] ?? "unknown",
    compile: cargoErrors.length === 0 && check.status === 0 ? "ok" : "error",
    cargoErrors: cargoErrors.map((e) => e.code),
    fingerprints,
  };
}

function runAll(): any[] {
  const records: any[] = [];
  for (const name of fixtureNames()) {
    const rec = runFixture(name);
    records.push(rec);
    const flags = rec.fingerprints.filter((f) => !f.startsWith("OK|")).join(" ; ");
    console.log(rec.fixture + "\t" + rec.construct + "\t" + rec.compile + "\t" + (flags || "-"));
  }
  return records;
}

function readRecords(path: string): any[] {
  return readFileSync(path, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

function writeJsonl(records: any[], outPath: string): void {
  mkdirSync(dirname(resolve(outPath)), { recursive: true });
  writeFileSync(outPath, records.map((r) => JSON.stringify(r)).join("\n") + "\n");
}

function fingerprintSet(records: any[]): Set<string> {
  const s = new Set<string>();
  for (const r of records) for (const f of r.fingerprints) s.add(f);
  return s;
}

function main(): void {
  const args = process.argv.slice(2);
  const mode = args[0];
  if (mode === "run" || mode === "baseline") {
    const i = args.indexOf("--out");
    const outPath = i >= 0 ? args[i + 1] : join(OUT_ROOT, "reports", "current.jsonl");
    const records = runAll();
    writeJsonl(records, outPath);
    console.log("wrote " + records.length + " records -> " + outPath);
    return;
  }
  if (mode === "diff") {
    const basePath = args[1];
    const curPath = args[2];
    if (!basePath || !curPath) { console.error("usage: harness.ts diff BASE CUR"); process.exit(2); }
    const base = fingerprintSet(readRecords(basePath));
    const cur = fingerprintSet(readRecords(curPath));
    const lines: string[] = [];
    for (const f of [...cur].sort()) lines.push((base.has(f) ? "unchanged" : "new") + "\t" + f);
    for (const f of [...base].sort()) if (!cur.has(f)) lines.push("disappeared\t" + f);
    console.log(lines.join("\n"));
    return;
  }
  console.error("usage: harness.ts run|baseline|diff");
  process.exit(2);
}

main();
