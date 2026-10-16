// Unit coverage report for boring's own bundles (P7.4).
//
// For each bundle it derives the compilation units the driver's test
// recipe actually type-checks (Plan.testSteps) and runs them in
// dependency order. A unit that ran and passed is CHECKED, one that ran
// and failed is FAILED, and a unit that was never invoked because an
// upstream unit failed is NOT_OBSERVED - so a downstream compile that a
// broken upstream masked reads NOT_OBSERVED, never "0 errors".
//
//   bun tools/unit-coverage-report.ts [--bundle <id>] [--list]
//
// --list prints the derived units without running anything.
// Exit 0 when every unit is CHECKED (or SKIPPED: toolchain absent);
// exit 1 when any unit FAILED (NOT_OBSERVED units ride along).

import { readFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

type Bundle = {
  id: string;
  target: string;
  rootsFile?: string;
  haxeArgs?: string[];
  build?: { args?: string[] };
  precision?: string;
};

type Project = {
  outRoot: string;
  sourceRoots: string[];
  bundles: Bundle[];
};

type Unit = {
  id: string;
  name: string;
  command: string;
  args: string[];
  cwd: string;
  dependsOn: string | null;
};

type Report = {
  bundle: string;
  target: string;
  units: { id: string; name: string; status: 'CHECKED' | 'FAILED' | 'NOT_OBSERVED' | 'SKIPPED'; note?: string }[];
};

function stripJsonComments(s: string): string {
  return s
    .replace(/\/\/[^\n]*/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '');
}

function walk(dir: string, suffix: string): string[] {
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = dir + '/' + e.name;
    if (e.isDirectory()) out.push(...walk(p, suffix));
    else if (e.name.endsWith(suffix)) out.push(p);
  }
  return out.sort();
}

function toolMissing(cmd: string): boolean {
  const r = spawnSync('sh', ['-c', 'command -v "$0" >/dev/null 2>&1', cmd]);
  return r.status !== 0;
}

function defineValue(haxeArgs: string[] | undefined, name: string): string | null {
  if (!haxeArgs) return null;
  for (let i = 0; i + 1 < haxeArgs.length; i++) {
    const next = haxeArgs[i + 1]!;
    if (haxeArgs[i] === '-D' && next.startsWith(name + '=')) {
      return next.slice(name.length + 1);
    }
  }
  return null;
}

function buildArgs(bundle: Bundle): string[] {
  return bundle.build?.args ?? [];
}

// The compilation units of one bundle, mirroring Plan.testSteps'
// build steps (the steps that type-check) and their dependency order.
function deriveUnits(proj: Project, bundle: Bundle, root: string): Unit[] {
  const t = bundle.target;
  const gen = `${root}/${proj.outRoot}/${bundle.id}/gen`;
  const genTests = `${root}/${proj.outRoot}/${bundle.id}/gen-tests`;
  const build = `${root}/${proj.outRoot}/${bundle.id}/build`;
  if (!existsSync(build)) mkdirSync(build, { recursive: true });

  if (t === 'kotlin') {
    const genFiles = walk(gen, '.kt');
    const testFiles = walk(genTests, '.kt');
    return [
      { id: 'main', name: 'build library jar', command: 'kotlinc', cwd: root, dependsOn: null,
        args: [...genFiles, ...buildArgs(bundle), '-include-runtime', '-d', `${build}/library.jar`] },
      { id: 'test', name: 'build tests jar', command: 'kotlinc', cwd: root, dependsOn: 'main',
        args: ['-cp', `${build}/library.jar`, ...testFiles, ...buildArgs(bundle), '-d', `${build}/tests.jar`] },
    ];
  }
  if (t === 'swift') {
    const module = defineValue(bundle.haxeArgs, 'swift-test-import') ?? '<missing-swift-test-import>';
    const genFiles = walk(gen, '.swift');
    const testFiles = walk(genTests, '.swift');
    const libName = `lib${module}.so`;
    return [
      { id: 'main', name: 'build library', command: 'swiftc', cwd: root, dependsOn: null,
        args: ['-emit-library', '-emit-module', ...genFiles, ...buildArgs(bundle), '-module-name', module, '-o', `${build}/${libName}`] },
      { id: 'test', name: 'build test executable', command: 'swiftc', cwd: root, dependsOn: 'main',
        args: [...testFiles, ...buildArgs(bundle), '-I', build, '-L', build, '-l', module, '-o', `${build}/test-runner`] },
    ];
  }
  if (t === 'haxe') {
    const main = defineValue(bundle.haxeArgs, 'haxe-test-main') ?? 'TestMain';
    const args = ['-cp', genTests];
    for (const r of proj.sourceRoots) { args.push('-cp'); args.push(r); }
    args.push(...buildArgs(bundle), '-main', main, '-js', `${gen}/test-main.js`);
    return [{ id: 'build', name: 'build test main', command: 'haxe', cwd: root, dependsOn: null, args }];
  }
  if (t === 'rust') {
    return [{ id: 'build', name: 'cargo test --no-run', command: 'cargo', cwd: gen, dependsOn: null,
      args: ['test', '--no-run', ...buildArgs(bundle)] }];
  }
  if (t === 'ts') {
    return [{ id: 'run', name: 'bun test', command: 'bun', cwd: root, dependsOn: null,
      args: ['test', genTests] }];
  }
  if (t === 'dart') {
    return [{ id: 'run', name: 'dart main', command: 'dart', cwd: root, dependsOn: null,
      args: [`${genTests}/main.dart`] }];
  }
  throw new Error(`bundle "${bundle.id}": target "${t}" has no coverage recipe`);
}

function run(cmd: string, args: string[], cwd: string): { rc: number | null; tail: string } {
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const combined = ((r.stdout ?? '') + (r.stderr ?? '')).trim();
  const tail = combined.split('\n').slice(-14).join('\n');
  return { rc: r.status, tail };
}

function main(): number {
  const argv = process.argv.slice(2);
  let onlyBundle: string | null = null;
  let listOnly = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--bundle') onlyBundle = argv[++i] ?? null;
    else if (argv[i] === '--list') listOnly = true;
  }

  const root = process.cwd();
  const proj: Project = JSON.parse(stripJsonComments(readFileSync(`${root}/boring.json`, 'utf8')));

  const reports: Report[] = [];
  let anyFailed = false;

  for (const bundle of proj.bundles) {
    if (onlyBundle && bundle.id !== onlyBundle) continue;
    const units = deriveUnits(proj, bundle, root);
    const statuses = new Map<string, 'CHECKED' | 'FAILED' | 'NOT_OBSERVED' | 'SKIPPED'>();
    const notes = new Map<string, string>();

    for (const u of units) {
      if (listOnly) { statuses.set(u.id, 'CHECKED'); continue; }
      if (toolMissing(u.command)) { statuses.set(u.id, 'SKIPPED'); notes.set(u.id, `${u.command} not on PATH`); continue; }
      const dep = u.dependsOn ? statuses.get(u.dependsOn) : undefined;
      if (dep === 'FAILED' || dep === 'NOT_OBSERVED') {
        statuses.set(u.id, 'NOT_OBSERVED');
        notes.set(u.id, `upstream ${u.dependsOn} did not type-check`);
        continue;
      }
      const res = run(u.command, u.args, u.cwd);
      if (res.rc === 0) { statuses.set(u.id, 'CHECKED'); }
      else {
        statuses.set(u.id, 'FAILED');
        anyFailed = true;
        notes.set(u.id, res.tail || `exit ${res.rc}`);
      }
    }

    reports.push({
      bundle: bundle.id, target: bundle.target,
      units: units.map(u => ({ id: u.id, name: u.name, status: statuses.get(u.id)!, note: notes.get(u.id) })),
    });
  }

  let failed = 0, observed = 0, skipped = 0, checked = 0;
  for (const rep of reports) {
    console.log(`bundle ${rep.bundle} (${rep.target})`);
    for (const u of rep.units) {
      const tag = u.status;
      if (tag === 'CHECKED') checked++;
      else if (tag === 'FAILED') failed++;
      else if (tag === 'NOT_OBSERVED') observed++;
      else if (tag === 'SKIPPED') skipped++;
      const pad = ' '.repeat(Math.max(1, 10 - tag.length));
      console.log(`  ${u.status}${pad}${u.name}`);
      if (u.note) console.log(`           └─ ${u.note.replace(/\n/g, '\n           │  ')}`);
    }
  }
  console.log(`\nunit-coverage-report: bundles=${reports.length} checked=${checked} failed=${failed} not_observed=${observed} skipped=${skipped}`);
  return anyFailed ? 1 : 0;
}

process.exit(main());
