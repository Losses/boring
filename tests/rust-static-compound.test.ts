import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * A ThreadSafeShared static is emitted as Mutex<T>, and every access takes the
 * lock on its own. A Haxe function that reads the table tail and appends to it
 * therefore has two lock acquisitions with user work between them, so two
 * threads can interleave the read and the append and the stored entries stop
 * matching their indices. This is the tiqian plan-width defect: a power table
 * grown by reading its tail serialized 144 as 0.009216.
 *
 * The emitter now diagnoses that shape (RustStaticCompound). The three tests
 * below cover the rejection, the shape of the required rewrite, and the
 * runtime result of that rewrite under 8 threads.
 */

type HaxeRun = { status: number | null; output: string };
type CargoRun = { status: number; output: string };

const root = path.resolve(import.meta.dir, "..");
const acceptedHxml = "tests/haxe/rust-static-compound/gen/rust.hxml";
const rejectedHxml = "tests/haxe/rust-static-compound/gen/race.hxml";

function makeScratch(tag: string): string {
  const dir = path.join(root, "out", "rust-static-compound", tag + "-" + randomUUID());
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function runHaxe(hxml: string, out: string): HaxeRun {
  const run = Bun.spawnSync(["haxe", hxml, "-D", "rust-output=" + out], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  return { status: run.exitCode, output: run.stdout.toString() + run.stderr.toString() };
}

function addIntegrationTest(out: string, name: string, source: string): void {
  fs.mkdirSync(path.join(out, "tests"), { recursive: true });
  fs.writeFileSync(path.join(out, "tests", name + ".rs"), source);
  // Generated crates set autotests = false, so the test target is explicit.
  fs.appendFileSync(out + "/Cargo.toml", '\n[[test]]\nname = "' + name + '"\npath = "tests/' + name + '.rs"\n');
}

function cargoTest(out: string): CargoRun {
  const run = Bun.spawnSync(["cargo", "test", "--quiet", "--test", "concurrent_publish"], {
    cwd: out,
    stdout: "pipe",
    stderr: "pipe",
  });
  return { status: run.exitCode ?? 1, output: run.stdout.toString() + run.stderr.toString() };
}

test("the read-then-append shape is rejected at generation time", () => {
  const out = makeScratch("reject");
  const run = runHaxe(rejectedHxml, out);
  expect(run.status, run.output).not.toBe(0);
  expect(run.output).toContain("static probe.StaticCompoundRace.table is shared through a Mutex");
  expect(run.output).toContain("Build the new value once and assign the static in a single write");
  expect(run.output).toContain("P-1a compound operation");
  // The rejection stops the emission of the module that carries the unsafe
  // body, so no crate with the read-then-append function exists.
  expect(fs.existsSync(path.join(out, "probe", "static_compound_race.rs"))).toBe(false);
}, 240000);

test("the accepted form builds a local table and publishes it with one assignment", () => {
  const out = makeScratch("shape");
  const run = runHaxe(acceptedHxml, out);
  expect(run.status, run.output).toBe(0);
  const src = fs.readFileSync(path.join(out, "probe", "static_compound_once.rs"), "utf8");
  // The growth loop appends to the local builder, never to the shared static.
  expect(src).toContain("let mut built = vec![1];");
  expect(src).not.toContain("STATIC_COMPOUND_ONCE_TABLE.lock().unwrap_or_else(|e| e.into_inner()).push(");
  // The shared table receives one complete value, and its value reads no
  // static, so two threads publish equal tables.
  expect(src).toContain("= StaticCompoundOnce::static_compound_once_build_table(k);");
  const publishLine = src.split("\n").find((line) => line.includes("= StaticCompoundOnce::static_compound_once_build_table(k);"));
  expect(publishLine).toBeDefined();
  expect(publishLine!).toContain("STATIC_COMPOUND_ONCE_TABLE.lock()");
}, 240000);

test("8 threads publish and read the table for 500 rounds with the baseline result", () => {
  const out = makeScratch("runtime");
  const run = runHaxe(acceptedHxml, out);
  expect(run.status, run.output).toBe(0);
  addIntegrationTest(
    out,
    "concurrent_publish",
    `use generated::probe::static_compound_once::StaticCompoundOnce;
use std::sync::{Arc, Barrier};

const EXPECTED: u32 = 531441; // 3^12, the value of table[12]
const ROUNDS: u32 = 500;
const THREADS: usize = 8;

#[test]
fn concurrent_publish_matches_the_single_thread_baseline() {
    assert_eq!(StaticCompoundOnce::static_compound_once_value_at(12), EXPECTED);
    StaticCompoundOnce::static_compound_once_reset();
    let mut corrupted = 0u32;
    for _ in 0..ROUNDS {
        StaticCompoundOnce::static_compound_once_reset();
        let barrier = Arc::new(Barrier::new(THREADS));
        let mut handles = Vec::new();
        for _ in 0..THREADS {
            let gate = Arc::clone(&barrier);
            handles.push(std::thread::spawn(move || {
                gate.wait();
                StaticCompoundOnce::static_compound_once_value_at(12)
            }));
        }
        for handle in handles {
            if handle.join().unwrap() != EXPECTED {
                corrupted += 1;
            }
        }
    }
    assert_eq!(corrupted, 0, "{} reads disagreed with the baseline", corrupted);
}
`,
  );
  const result = cargoTest(out);
  expect(result.status, result.output).toBe(0);
}, 600000);
