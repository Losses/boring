import { expect, test } from "bun:test";
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

/**
 * The three static/global realizations of the Rust target (policy P-1a).
 *
 * The compiler checks every emitted static against its declared mode at
 * generation time (RustStaticRealization.verifyItem), so a mismatch stops
 * generation. This file checks the same invariant on the built tree, which
 * is the tree audit the policy names, and it checks the two shapes the
 * policy forbids outright: an unconditional unsafe Send/Sync wrapper over
 * Rc/RefCell, and a ThreadAffine value inside a process-global slot.
 */

const REPO_ROOT = resolve(import.meta.dir, "..");
const GEN = join(REPO_ROOT, "reference", "rust", "gen");
const RUNTIME_SOURCE = join(REPO_ROOT, "packages", "compiler", "reflaxe", "rust", "rustcompiler", "RustRuntime.hx");

type StaticKind = "thread-local" | "static";
type StaticItem = { file: string; item: string; kind: StaticKind };
type RunResult = { status: number | null; output: string };

function allRustFiles(dir: string): string[] {
  const out: string[] = [];
  const walk = (current: string): void => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(path);
      } else if (entry.name.endsWith(".rs")) {
        out.push(path);
      }
    }
  };
  if (existsSync(dir)) {
    walk(dir);
  }
  return out;
}

/** Every static declaration in the tree: a plain static item, or the
 * declared static of one `thread_local!` block. */
function staticItems(files: readonly string[]): StaticItem[] {
  const items: StaticItem[] = [];
  for (const file of files) {
    const lines = readFileSync(file, "utf8").split("\n");
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim();
      if (line.startsWith("thread_local! {")) {
        const block: string[] = [];
        for (let cursor = index; cursor < lines.length; cursor += 1) {
          block.push(lines[cursor]);
          if (lines[cursor].trim() === "}") {
            break;
          }
        }
        const declaration = block.find((entry) => /^(pub )?static /.test(entry.trim()));
        items.push({ file, item: declaration === undefined ? block.join(" ") : declaration.trim(), kind: "thread-local" });
        // The block's own lines are part of the collected item; skip them so
        // the declared static is not counted twice.
        index += block.length - 1;
      } else if (/^(pub )?static [A-Za-z0-9_]+:/.test(line)) {
        items.push({ file, item: line, kind: "static" });
      }
    }
  }
  return items;
}

function runHaxe(args: readonly string[], cwd: string): RunResult {
  const run = spawnSync("haxe", args, { cwd, encoding: "utf8" });
  return { status: run.status, output: (run.stdout ?? "") + (run.stderr ?? "") };
}

test("the runtime carries no unconditional Send/Sync wrapper over Rc or RefCell", () => {
  const runtime = readFileSync(RUNTIME_SOURCE, "utf8");
  expect(runtime).not.toContain("unsafe impl");
  expect(runtime).not.toContain("SingleThread");
});

test("every static declares a mode that matches its emitted Rust item", () => {
  const files = allRustFiles(GEN);
  expect(files.length).toBeGreaterThan(0);
  const items = staticItems(files);
  expect(items.length).toBeGreaterThan(0);
  for (const { file, item, kind } of items) {
    const where = file + ": " + item;
    // No emitted static names the retired wrapper.
    expect(where).not.toContain("SingleThread");
    if (kind === "thread-local") {
      // ThreadAffine: an owner-thread slot over a value that is not Sync
      // (an Rc, or a RefCell whose contents are not Sync), never a
      // process-global LazyLock or Mutex.
      expect(where).toMatch(/Rc<|RefCell</);
      expect(where).not.toContain("Mutex<");
      expect(where).not.toContain("LazyLock<");
    } else if (item.indexOf("Mutex<") >= 0) {
      // ThreadSafeShared: a process slot with a Mutex and no Rc/RefCell.
      expect(where).not.toContain("Rc<");
      expect(where).not.toContain("RefCell<");
    } else if (item.indexOf("LazyLock<") >= 0) {
      // ImmutableLazy: a LazyLock slot with no lock inside.
      expect(where).not.toContain("Mutex<");
      expect(where).not.toContain("RefCell<");
    } else {
      // ImmutableLazy direct form: a plain immutable static.
      expect(where).not.toContain("Rc<");
      expect(where).not.toContain("RefCell<");
    }
  }
});

/** A probe class whose static holds a class handle, so the compilation
 * emits a ThreadAffine static and the harness gate is observable. */
const PROBE_SOURCE = `package probe;

class Holder {
    public function new() {}
}

class StaticProbe {
    public static final instance:Holder = new Holder();

    public static function label():String {
        return "probe";
    }
}
`;

function writeProbe(): string {
  const dir = join(REPO_ROOT, "out", "static-realization", "probe");
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, "probe"), { recursive: true });
  writeFileSync(join(dir, "probe", "StaticProbe.hx"), PROBE_SOURCE);
  expect(existsSync(join(dir, "probe", "StaticProbe.hx"))).toBe(true);
  writeFileSync(
    join(dir, "gen.hxml"),
    [
      "-lib reflaxe",
      "-lib boring",
      "-cp packages/compiler",
      "-cp packages/compiler/reflaxe/rust/std-shadow",
      "-cp packages/compiler/reflaxe/rust",
      "-cp samples",
      "-cp samples/haxe",
      "-cp " + dir,
      "--macro Intercept.run(['" + dir + "'])",
      "--macro rustcompiler.Compiler.use()",
      "-D runtime-import=crate::runtime",
      "-D runtime-emit=runtime",
      "-D rust-output=" + join(dir, "gen"),
      "probe.StaticProbe",
      "",
    ].join("\n"),
  );
  return dir;
}

test("the serial harness is accepted and the parallel harness is rejected for ThreadAffine", () => {
  const dir = writeProbe();
  try {
    const serial = runHaxe([join(dir, "gen.hxml"), "-D", "rust-test-threads=serial"], REPO_ROOT);
    expect(serial.status, serial.output).toBe(0);
    const generated = readFileSync(join(dir, "gen", "probe", "static_probe.rs"), "utf8");
    expect(generated).toContain("thread_local! {");
    expect(generated).toContain("pub static STATIC_PROBE_INSTANCE: Rc<RefCell<Holder>> =");

    const parallel = runHaxe([join(dir, "gen.hxml"), "-D", "rust-test-threads=parallel"], REPO_ROOT);
    expect(parallel.status).not.toBe(0);
    expect(parallel.output).toContain("rust-test-threads=parallel");
    expect(parallel.output).toContain("ThreadAffine");

    // A value that names no harness is a generation error as well: it would
    // otherwise select neither harness and leave the cargo default scheduler
    // in place. The bare define sets "1".
    const misspelled = runHaxe([join(dir, "gen.hxml"), "-D", "rust-test-threads=paralel"], REPO_ROOT);
    expect(misspelled.status).not.toBe(0);
    expect(misspelled.output).toContain("must be serial or parallel");

    const bare = runHaxe([join(dir, "gen.hxml"), "-D", "rust-test-threads"], REPO_ROOT);
    expect(bare.status).not.toBe(0);
    expect(bare.output).toContain("must be serial or parallel");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}, 180000);
