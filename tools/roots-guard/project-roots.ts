import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * The generation lines of one bundle of a project file, as HXML text.
 *
 * Boring's own entry point is boring.json: each bundle takes its module roots
 * from a named source set and the remaining arguments from its haxeArgs. The
 * roots guard and the registry trace still need a direct haxe invocation, so
 * they derive that view here from the project file and read no hand-written
 * roots file. The derivation mirrors Plan.genArgs: sourceRoots classpaths, the project's
 * arguments, the bundle's arguments, the source set's module roots, then the
 * derived output defines and the precision define.
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
    sourceRoots: string[];
    haxeArgs?: string[];
    sourceSets?: Record<string, { types?: string[] }>;
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

/**
 * One HXML line per argument pair: a flag followed by a non-flag token is
 * joined, every other token (a module root) stands alone. No value in this
 * project starts with "-", so the mapping is exact.
 */
export function renderArguments(args: string[]): string[] {
    const lines: string[] = [];
    for(let index = 0; index < args.length; index++) {
        const token = args[index] ?? "";
        const next = args[index + 1];
        if(token.startsWith("-") && next !== undefined && next !== "" && !next.startsWith("-")) {
            lines.push(token + " " + next);
            index++;
        } else {
            lines.push(token);
        }
    }
    return lines;
}

export interface RootsLinesOptions {
    /** Output tree; defaults to <outRoot>/<id>/gen. */
    output?: string;
    /** Generated-test tree; defaults to <outRoot>/<id>/gen-tests. */
    testOutput?: string;
}

/** The HXML lines a direct haxe invocation of one bundle needs. */
export function projectRootsLines(id: string, options: RootsLinesOptions = {}, doc: ProjectDoc = readProject()): string[] {
    const bundle = projectBundle(doc, id);
    const lines: string[] = [];
    for(const root of doc.sourceRoots) lines.push("-cp " + root);
    // Plan.genArgs holds these at their documented defaults before the
    // project's arguments; a direct haxe invocation needs them spelled out.
    if(bundle.target === "ts") lines.push("-D ts-test-runner=bun");
    if(bundle.target === "dart") lines.push("-D dart-test-runner=native");
    if(bundle.target === "swift") lines.push("-D swift-test-runner=native");
    if(doc.haxeArgs !== undefined) lines.push(...renderArguments(doc.haxeArgs));
    if(bundle.haxeArgs !== undefined) lines.push(...renderArguments(bundle.haxeArgs));
    if(bundle.target !== "haxe") {
        const genDir = options.output ?? join(REPO_ROOT, doc.outRoot, bundle.id, "gen");
        const genTestsDir = options.testOutput ?? join(REPO_ROOT, doc.outRoot, bundle.id, "gen-tests");
        lines.push("-D " + bundle.target + "-output=" + genDir);
        lines.push("-D " + bundle.target + "-test-output=" + genTestsDir);
    }
    if(bundle.precision === "f32") lines.push("-D float-precision=f32");
    if(bundle.sourceSet !== undefined) {
        const set = doc.sourceSets === undefined ? undefined : doc.sourceSets[bundle.sourceSet];
        for(const type of set?.types ?? []) lines.push(type);
    }
    return lines;
}
