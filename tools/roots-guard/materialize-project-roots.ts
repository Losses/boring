import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { projectRootsLines, readProject } from "./project-roots";

/**
 * Writes one roots HXML per bundle of boring.json into the given directory.
 *
 * Boring's own project declares its module roots in sourceSets and its
 * generation arguments in the bundles' haxeArgs; it ships no hand-written roots
 * file. The roots guard reads HXML, so check:roots materializes that view from
 * the project file first and then runs the guard against it. The output is
 * throwaway (a temporary directory or out/), is never read by generation, and
 * is rebuilt on every gate run, so it cannot drift from the project file.
 *
 * Usage: bun tools/roots-guard/materialize-project-roots.ts <out-dir>
 */

const outDir = process.argv[2];
if(!outDir) {
    console.error("usage: materialize-project-roots.ts <out-dir>");
    process.exit(2);
}

const doc = readProject();
mkdirSync(outDir, { recursive: true });
for(const bundle of doc.bundles) {
    const path = join(outDir, bundle.id + ".hxml");
    const header = [
        "# Materialized from boring.json by tools/roots-guard/materialize-project-roots.ts.",
        "# Generated view: edit the project file, never this file.",
    ];
    writeFileSync(path, header.concat(projectRootsLines(bundle.id, {}, doc)).join("\n") + "\n");
    console.log("[materialize] " + bundle.id + " -> " + path);
}
