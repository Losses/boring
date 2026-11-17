import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Reads boring's own project file and derives the haxe command line of one
 * bundle the same way the bundle driver does.
 *
 * Boring's own generation entry is boring.json: every bundle names a source
 * set whose module roots travel on the command line, and its remaining
 * arguments live in `haxeArgs`. Tests that need a direct haxe invocation (a
 * probe module appended to the reference set, a generation redirected into a
 * temporary tree) used to spawn a hand-written `examples/*.hxml`; that file
 * is gone, so they derive the arguments from the one copy and keep no second
 * one. The derivation order mirrors Plan.genArgs: sourceRoots
 * classpaths, the target's document defaults, the project arguments, the
 * bundle arguments, the source set's module roots, then the derived output
 * defines and precision.
 */

export const REPO_ROOT = resolve(import.meta.dir, "..", "..");

export interface ProjectBundle {
  id: string;
  target: string;
  precision?: string;
  sourceSet?: string;
  haxeArgs?: string[];
}

export interface ProjectDoc {
  outRoot: string;
  resultsDir?: string;
  sourceRoots: string[];
  haxeArgs?: string[];
  sourceSets?: Record<string, { types?: string[]; packages?: string[] }>;
  bundles: ProjectBundle[];
}

/** JSONC: boring.json may carry whole-line // comments. */
export function readProject(path: string = join(REPO_ROOT, "boring.json")): ProjectDoc {
  const raw = readFileSync(path, "utf8");
  const json = raw
    .split("\n")
    .filter((line) => !/^\s*\/\//.test(line))
    .join("\n");
  return JSON.parse(json) as ProjectDoc;
}

export function projectBundle(doc: ProjectDoc, id: string): ProjectBundle {
  const bundle = doc.bundles.find((entry) => entry.id === id);
  if(bundle === undefined) {
    throw new Error("boring.json declares no bundle " + JSON.stringify(id));
  }
  return bundle;
}

export interface GenArgsOptions {
  /** Output tree; defaults to <outRoot>/<id>/gen like the driver. */
  output?: string;
  /** Generated-test tree; defaults to <outRoot>/<id>/gen-tests. */
  testOutput?: string;
}

/** The command-line arguments haxe receives for one bundle's generation. */
export function genArgs(id: string, options: GenArgsOptions = {}): string[] {
  const doc = readProject();
  const bundle = projectBundle(doc, id);
  const args: string[] = [];
  for(const root of doc.sourceRoots) args.push("-cp", root);
  if(bundle.target === "ts") args.push("-D", "ts-test-runner=bun");
  if(bundle.target === "dart") args.push("-D", "dart-test-runner=native");
  if(bundle.target === "swift") args.push("-D", "swift-test-runner=native");
  for(const arg of doc.haxeArgs ?? []) args.push(arg);
  for(const arg of bundle.haxeArgs ?? []) args.push(arg);
  if(bundle.sourceSet !== undefined) {
    const set = doc.sourceSets === undefined ? undefined : doc.sourceSets[bundle.sourceSet];
    for(const type of set?.types ?? []) args.push(type);
  }
  if(bundle.target !== "haxe") {
    args.push("-D", bundle.target + "-output=" + (options.output ?? join(REPO_ROOT, doc.outRoot, bundle.id, "gen")));
    args.push("-D", bundle.target + "-test-output=" + (options.testOutput ?? join(REPO_ROOT, doc.outRoot, bundle.id, "gen-tests")));
  }
  if(bundle.precision === "f32") args.push("-D", "float-precision=f32");
  return args;
}

/**
 * Replaces the values of existing `-D key=...` defines and drops the ones a
 * caller sets to undefined; new keys are appended last, so haxe keeps them
 * (it keeps the last value of a repeated define).
 */
export function withDefines(args: string[], overrides: Record<string, string | undefined>): string[] {
  const keys = new Set(Object.keys(overrides));
  const kept: string[] = [];
  for(let index = 0; index < args.length; index++) {
    const token = args[index] ?? "";
    const value = args[index + 1];
    if(token === "-D" && value !== undefined) {
      const match = /^([^=]+)=/.exec(value);
      if(match !== null && keys.has(match[1] ?? "")) {
        index++;
        continue;
      }
    }
    kept.push(token);
  }
  for(const [key, value] of Object.entries(overrides)) {
    if(value !== undefined) kept.push("-D", key + "=" + value);
  }
  return kept;
}
