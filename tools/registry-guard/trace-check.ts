#!/usr/bin/env bun
/**
 * Shared-module consumption trace.
 *
 * Replaces the source-text backstop. The old check required a module name to
 * appear in a target compiler's source, which passes for a dead reference and
 * says nothing about a target that ships its own copy. This check compiles the
 * standard behavior corpus to every target with `-D shared-module-trace`, and
 * the shared mechanisms record the caller of every public entry point that
 * actually runs. A module the registry expects but the trace never sees is a
 * bypass: the target produced that behavior without the shared implementation.
 *
 * The registry (SemanticPassRegistry.hx) stays the source of truth: the
 * compilation writes out/shared-module-consumers.json, and this runner asserts
 * exactly that table. Attribution at the direct caller is preserved in the
 * trace and reported as a warning when a module is only reached through
 * another shared mechanism, so a dead direct wrapper stays visible without
 * turning a genuinely consumed module red.
 *
 * Usage: bun tools/registry-guard/trace-check.ts [target ...]
 *
 * Exit status: 0 every expected (module, target) pair appears in the trace;
 * 1 a trace is missing, a compile fails, or a module is absent; 2 setup error.
 */

import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";

const repoRoot = resolve(import.meta.dir, "..", "..");
const traceRoot = join(repoRoot, "out", "shared-module-trace");
const consumersPath = join(repoRoot, "out", "shared-module-consumers.json");
const examplesRoot = join(repoRoot, "examples");

const ALL_TARGETS = ["dart", "kotlin", "rust", "swift", "ts"] as const;
type Target = (typeof ALL_TARGETS)[number];

type ConsumerRow = { module: string; targets: string[] };
type ConsumerTable = { modules: ConsumerRow[] };

const requested = process.argv.slice(2).filter((arg) => !arg.startsWith("-"));
const targets: Target[] = requested.length === 0 ? [...ALL_TARGETS] : (requested as Target[]);
for (const target of targets) {
    if (!ALL_TARGETS.includes(target)) {
        console.error("trace-check: unknown target " + target);
        process.exit(2);
    }
}

/** Output defines each target's hxmls read; the trace run writes beside out/. */
const outputDefines: Record<Target, string[]> = {
    dart: ["dart-output", "dart-test-output"],
    kotlin: ["kotlin-output", "kotlin-test-output"],
    rust: ["rust-output"],
    swift: ["swift-output", "swift-test-output"],
    ts: ["ts-output", "ts-test-output"],
};

/** One parsed trace: module -> set of calling classes. */
type Trace = Map<string, Set<string>>;

/** One target's compile result. */
type TargetRun = { trace: Trace; status: number };

/** A registry row that did not appear in a target trace. */
type MissingRow = { module: string; target: Target };

/** A registry row that ran, but only from another shared mechanism. */
type TransitiveRow = { module: string; target: Target; callers: string[] };

function readTrace(path: string): Trace {
    const trace: Trace = new Map();
    if (!existsSync(path)) {
        return trace;
    }
    for (const line of readFileSync(path, "utf8").split("\n")) {
        if (line.length === 0) continue;
        const tab = line.indexOf("\t");
        if (tab < 0) continue;
        const module = line.slice(0, tab);
        const caller = line.slice(tab + 1);
        const callers = trace.get(module) ?? new Set<string>();
        callers.add(caller);
        trace.set(module, callers);
    }
    return trace;
}

function firstTargetCaller(callers: Set<string> | undefined, target: Target): string | null {
    if (callers === undefined) return null;
    const prefix = target + "compiler.";
    for (const caller of callers) {
        if (caller.startsWith(prefix)) return caller;
    }
    return null;
}

/**
 * The trace corpus is the target's own generation corpus. The one exclusion
 * is tests.DriverPlanTests: it pulls in driver.Config, whose StepOverride
 * object literal the dart and swift emitters reject on the current baseline,
 * so keeping it would make the settled targets and the unsettled ones
 * incomparable. The hxml is derived here rather than checked in, so the
 * corpus cannot drift from examples/<target>.hxml.
 */
function traceHxml(target: Target): string {
    const source = readFileSync(join(examplesRoot, target + ".hxml"), "utf8");
    const lines = source.split("\n").filter((line) => line.trim() !== "tests.DriverPlanTests");
    const dir = join(traceRoot, target);
    mkdirSync(dir, { recursive: true });
    const path = join(dir, "trace.hxml");
    writeFileSync(path, lines.join("\n"));
    return path;
}

function runTarget(target: Target): TargetRun {
    const dir = join(traceRoot, target);
    mkdirSync(dir, { recursive: true });
    const tracePath = join(dir, "trace.tsv");
    rmSync(tracePath, { force: true });
    // The shared mechanisms must come from this checkout. A stale haxelib copy
    // can shadow packages/compiler and silently compile an older Intercept,
    // so the checkout classpath goes first.
    const args = ["-cp", join(repoRoot, "packages/compiler"), traceHxml(target)];
    args.push("-D", "shared-module-trace=" + tracePath);
    args.push("-D", "shared-module-trace-target=" + target);
    for (const define of outputDefines[target]) {
        args.push("-D", define + "=" + join(dir, "gen"));
    }
    process.stdout.write("trace-check: compiling " + target + " ... ");
    const result = spawnSync("haxe", args, { cwd: repoRoot, encoding: "utf8" });
    const status = result.status ?? 1;
    if (status !== 0) {
        process.stdout.write("FAILED (" + status + ")\n");
        const output = (result.stdout ?? "") + (result.stderr ?? "");
        const tail = output.trim().split("\n").slice(-8).join("\n");
        if (tail.length > 0) console.error(tail);
    } else {
        process.stdout.write("ok\n");
    }
    return { trace: readTrace(tracePath), status };
}

if (!existsSync(consumersPath)) {
    // The table is emitted by any compile that runs Intercept.run. The first
    // trace compile writes it; a stale/absent file is retried after the runs.
    rmSync(consumersPath, { force: true });
}

const traces = new Map<Target, Trace>();
let failed = false;
for (const target of targets) {
    const run = runTarget(target);
    traces.set(target, run.trace);
    if (run.status !== 0) failed = true;
}

let table: ConsumerTable;
try {
    table = JSON.parse(readFileSync(consumersPath, "utf8")) as ConsumerTable;
} catch (error) {
    console.error("trace-check: cannot read " + consumersPath + ": " + error);
    console.error("trace-check: run a traced compile so Intercept.run emits the consumer table");
    process.exit(2);
}

/** Expected modules per target, inverted from the registry. */
const expected = new Map<Target, Set<string>>();
for (const target of targets) expected.set(target, new Set());

const missing: MissingRow[] = [];
const transitiveOnly: TransitiveRow[] = [];

for (const row of table.modules) {
    for (const rawTarget of row.targets) {
        if (!targets.includes(rawTarget as Target)) continue;
        const target = rawTarget as Target;
        expected.get(target)?.add(row.module);
        const callers = traces.get(target)?.get(row.module);
        if (callers === undefined) {
            missing.push({ module: row.module, target });
            continue;
        }
        if (firstTargetCaller(callers, target) === null) {
            transitiveOnly.push({ module: row.module, target, callers: [...callers].sort() });
        }
    }
}

const width = 24;
const header = ["module".padEnd(width), ...targets.map((t) => t.padStart(8))].join(" ");
console.log("");
console.log(header);
console.log("-".repeat(header.length));
for (const row of table.modules) {
    const cells = targets.map((target) => {
        if (!expected.get(target)?.has(row.module)) return "-".padStart(8);
        const callers = traces.get(target)?.get(row.module);
        if (callers === undefined) return "MISSING".padStart(8);
        return (firstTargetCaller(callers, target) === null ? "via*" : "ok").padStart(8);
    });
    console.log([row.module.padEnd(width), ...cells].join(" "));
}
console.log("");
console.log("ok = a " + targets.join("/") + "compiler.* class called the module directly");
console.log("via* = the module ran, but only from another shared mechanism");
console.log("- = the registry does not expect this module from the target");

if (transitiveOnly.length > 0) {
    console.log("");
    console.log("transitive-only (consumed, no direct target caller):");
    for (const item of transitiveOnly) {
        console.log("  " + item.module + " @ " + item.target + " <- " + item.callers.join(", "));
    }
}

const unexpected = [...traces].flatMap(([target, trace]) =>
    [...trace.keys()]
        .filter((module) => !expected.get(target)?.has(module))
        .map((module) => ({ module, target })),
);
if (unexpected.length > 0) {
    console.log("");
    console.log("traced but not expected by the registry (informational):");
    for (const item of unexpected) console.log("  " + item.module + " @ " + item.target);
}

if (missing.length > 0 || failed) {
    console.log("");
    for (const item of missing) {
        console.error("trace-check: " + item.target + " never reached shared mechanism " + item.module);
    }
    process.exit(1);
}

console.log("");
console.log("trace-check: " + table.modules.length + " modules, " + targets.length + " targets, no bypass");
