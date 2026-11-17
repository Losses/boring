import { expect, test } from "bun:test";
import { mkdirSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { genArgs } from "./support/project-args";
import { availableParallelism } from "node:os";
import { join, relative, resolve, sep } from "node:path";

/**
 * Compile smoke for every observational hxml entry under tests/haxe/.
 *
 * The 219 hxml entries under `tests/haxe/` are observation fixtures: they compile
 * the generator (or an oracle) against one fixture and print or emit facts. Only
 * 40 of the 100 or so fixture directories have a collected test; the rest run
 * only when a human remembers to run them. The 2026-11 survey found three real
 * drifts (a removed SwiftType symbol, a widened SourceContainerFace switch, and a
 * spec-narrowed Dart key) that had been red for up to 1.5 months because nothing
 * compiled these entries in CI.
 *
 * This test does not run each fixture's run.sh (that needs the native target
 * toolchains the smoke deliberately avoids). It compiles every entry and asserts
 * one of two outcomes from `tests/haxe/fixtures.json`:
 *
 *   - mode "compile": `haxe <entry> [defines]` exits 0
 *   - mode "reject":  it exits non-zero AND its output contains the entry's
 *                     `diagnostic`; a passing compile is a failure here, because
 *                     these eight entries exist to prove a rejection
 *
 * The eight "reject" diagnostic substrings are pinned to the generator's
 * current wording on purpose: a wording change reds this smoke so the new
 * sentence is read and the substring updated. The compile/reject split is the
 * invariant; the sentence is the guard that a rejection did not silently
 * become a pass.
 *
 * Set equality is asserted first: the manifest must list every .hxml under
 * tests/haxe/ and nothing else. A new fixture that is not classified fails the
 * smoke; it is not skipped silently, which is the same rule the
 * fixture-reachability guard uses for its count.
 *
 * The two Haxe in-source test entries (test-main.hxml, test-main-f32.hxml)
 * compile against reference/haxe[-f32]/gen-tests, which is gitignored, so a
 * fresh checkout has no tree for them. This smoke generates both trees first,
 * with the arguments the haxe bundles carry in boring.json, so the pool never
 * races the tree it needs.
 *
 * Entries compile in parallel (BORING_HAXE_SMOKE_JOBS, default min(cpus, 6));
 * the per-entry scratch directory under out/haxe-compile-smoke/ is what the
 * tree-output defines point at, so no two entries write the same tree.
 */

const ROOT = resolve(import.meta.dir, "..");
const HAXE_DIR = join(ROOT, "tests", "haxe");
const MANIFEST_PATH = join(HAXE_DIR, "fixtures.json");
const SCRATCH = join(ROOT, "out", "haxe-compile-smoke");
const TARGETS = ["rust", "kotlin", "swift", "dart", "ts"];
const ENTRY_TIMEOUT_MS = 240_000;
const TEST_TIMEOUT_MS = 900_000;
const MAX_JOBS = 6;
const FAILURE_TAIL = 2500;

type Mode = "compile" | "reject";

interface Entry {
  path: string;
  mode: Mode;
  defines?: string[];
  diagnostic?: string;
  reason?: string;
  targets?: string[];
}

interface Manifest {
  defaults?: { treeOutputDefines?: boolean; outPlaceholder?: string; note?: string };
  prepareDirs?: string[];
  generateBundles?: string[];
  entries: Entry[];
}

interface Observation {
  entry: Entry;
  code: number;
  timedOut: boolean;
  seconds: number;
  output: string;
  args: string[];
}

/** Every .hxml under tests/haxe/, repo-relative, sorted. */
function walkHxml(dir: string): string[] {
  const found: string[] = [];
  for (const dirent of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, dirent.name);
    if (dirent.isDirectory()) found.push(...walkHxml(full));
    else if (dirent.isFile() && dirent.name.endsWith(".hxml")) {
      found.push(relative(ROOT, full).split(sep).join("/"));
    }
  }
  return found.sort();
}

function slugOf(entryPath: string): string {
  return entryPath.replace(/^tests\/haxe\//, "").replace(/[^A-Za-z0-9]+/g, "_");
}

function tail(text: string): string {
  const trimmed = text.trimEnd();
  return trimmed.length > FAILURE_TAIL ? "...\n" + trimmed.slice(-FAILURE_TAIL) : trimmed;
}

/**
 * Compiles one entry. Tree-output defines come from the hxml text: an entry that
 * enables <target>compiler.Compiler.use() without -D <target>-output fails with
 * "output directory ... is not defined", which is a caller-parameter gap rather
 * than a fixture defect, so the smoke supplies a per-entry tree. Per-entry
 * `defines` from the manifest are appended last.
 */
async function runEntry(manifest: Manifest, entry: Entry): Promise<Observation> {
  const out = join(SCRATCH, slugOf(entry.path));
  mkdirSync(out, { recursive: true });

  const args = ["haxe", entry.path];
  if (manifest.defaults?.treeOutputDefines !== false) {
    const text = readFileSync(join(ROOT, entry.path), "utf8");
    for (const target of TARGETS) {
      if (!text.includes(target + "compiler.Compiler.use()")) continue;
      args.push("-D", target + "-output=" + out + "/gen", "-D", target + "-test-output=" + out + "/gen-tests");
    }
  }
  const placeholder = manifest.defaults?.outPlaceholder ?? "<out>";
  for (const defineText of entry.defines ?? []) {
    args.push("-D", defineText.split(placeholder).join(out));
  }

  const started = Date.now();
  const proc = Bun.spawn(args, { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    proc.kill();
  }, ENTRY_TIMEOUT_MS);
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  clearTimeout(timer);
  return {
    entry,
    code: code ?? -1,
    timedOut,
    seconds: (Date.now() - started) / 1000,
    output: stderr + stdout,
    args,
  };
}

test(
  "every tests/haxe hxml entry compiles or rejects as tests/haxe/fixtures.json says",
  async () => {
    const manifest: Manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
    const listed = manifest.entries.map((entry) => entry.path);
    const actual = walkHxml(HAXE_DIR);

    const unlisted = actual.filter((path) => !listed.includes(path));
    const stale = listed.filter((path) => !actual.includes(path));
    expect(unlisted, "hxml entries missing from tests/haxe/fixtures.json (classify them so they are smoke-covered)").toEqual([]);
    expect(stale, "tests/haxe/fixtures.json lists paths that no longer exist").toEqual([]);
    expect(
      listed.filter((path, index) => listed.indexOf(path) !== index),
      "duplicate manifest entries",
    ).toEqual([]);
    expect(
      manifest.entries.filter(
        (entry) => (entry.mode !== "compile" && entry.mode !== "reject") || (entry.mode === "reject" && !entry.diagnostic),
      ),
      "manifest entries must be mode compile, or mode reject with a diagnostic",
    ).toEqual([]);

    const byPath = new Map(manifest.entries.map((entry) => [entry.path, entry]));

    rmSync(SCRATCH, { recursive: true, force: true });
    mkdirSync(SCRATCH, { recursive: true });
    for (const dir of manifest.prepareDirs ?? []) mkdirSync(join(ROOT, dir), { recursive: true });

    const wallStart = Date.now();
    const observations: Observation[] = [];
    // The two Haxe bundles generate the trees the in-source test entries
    // compile against; boring.json is the only copy of their arguments.
    for(const id of manifest.generateBundles ?? []) {
      const generation = Bun.spawn(["haxe", ...genArgs(id)], { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
      const [code, stderr] = await Promise.all([generation.exited, new Response(generation.stderr).text()]);
      if(code !== 0) {
        throw new Error("haxe smoke: generation of " + id + " failed (exit " + code + "): " + tail(stderr));
      }
    }

    const pool = manifest.entries;
    const jobs = Math.max(
      1,
      Math.min(Number(Bun.env.BORING_HAXE_SMOKE_JOBS ?? "") || availableParallelism(), MAX_JOBS),
    );
    const pooled: Observation[] = new Array(pool.length);
    let next = 0;
    async function worker(): Promise<void> {
      for (;;) {
        const index = next++;
        if (index >= pool.length) return;
        pooled[index] = await runEntry(manifest, pool[index]);
      }
    }
    await Promise.all(Array.from({ length: Math.min(jobs, pool.length) }, worker));

    const all = [...observations, ...pooled];
    const failures: string[] = [];
    let compiled = 0;
    let rejected = 0;
    for (const observation of all) {
      const head = observation.entry.path + " [" + observation.entry.mode + "]";
      if (observation.timedOut) {
        failures.push(head + ": timed out after " + ENTRY_TIMEOUT_MS + "ms\n" + tail(observation.output));
        continue;
      }
      if (observation.entry.mode === "compile") {
        if (observation.code === 0) compiled++;
        else failures.push(head + ": expected exit 0, got " + observation.code + "\n" + tail(observation.output));
        continue;
      }
      if (observation.code === 0) {
        failures.push(head + ": expected a diagnosed rejection, but it compiled (exit 0)");
        continue;
      }
      if (!observation.output.includes(observation.entry.diagnostic!)) {
        failures.push(
          head +
            ": exit " +
            observation.code +
            " but the expected diagnostic " +
            JSON.stringify(observation.entry.diagnostic) +
            " is absent\n" +
            tail(observation.output),
        );
        continue;
      }
      rejected++;
    }

    const wallSeconds = ((Date.now() - wallStart) / 1000).toFixed(1);
    const cpuSeconds = all.reduce((sum, observation) => sum + observation.seconds, 0).toFixed(1);
    console.log(
      "haxe compile smoke: " +
        all.length +
        " entries (" +
        compiled +
        " compiled, " +
        rejected +
        " rejected as designed, " +
        failures.length +
        " failed) in " +
        wallSeconds +
        "s wall / " +
        cpuSeconds +
        "s cpu with " +
        jobs +
        " jobs",
    );

    if (failures.length > 0) {
      throw new Error(
        "haxe compile smoke: " + failures.length + " failure(s)\n\n" + failures.join("\n\n"),
      );
    }
  },
  TEST_TIMEOUT_MS,
);
