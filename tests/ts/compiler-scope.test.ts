import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Boundary guard for the transpilation targets: a compiler must not
 * assume which package or sources it is compiling. Output is derived
 * from the typed AST or it does not ship; name-keyed emission tables
 * and hard-coded package directives are how the first Kotlin run
 * fabricated its output, so this scan holds both landed targets to
 * zero occurrences of the compiled sources' identifiers inside the
 * compiler sources.
 *
 * The standard namespaces the compilers ARE allowed to know are the
 * Haxe std modules (haxe.*) and the subset's own std pack, mirroring
 * the compiler-recognized namespaces of the entry configuration.
 */

const COMPILER_DIRECTORIES: readonly string[] = [
  "src",
  "src/reflaxe/ts/tscompiler",
  "src/reflaxe/kotlin/kotlincompiler",
];

/** Substrings that assume the compiled package or name the sample modules. */
const BANNED_SUBSTRINGS: readonly string[] = [
  "boring",
  "Vector",
  "Glyph",
  "BoundsEm",
  "BinaryReader",
  "BinaryWriter",
];

function haxeFiles(directory: string): string[] {
  return readdirSync(directory).filter((name) => name.endsWith(".hx"));
}

describe("compiler boundary: no compiled-package or sample names", () => {
  for(const directory of COMPILER_DIRECTORIES) {
    for(const file of haxeFiles(directory)) {
      const path = join(directory, file);
      test(`${path} carries no banned identifier`, () => {
        const source = readFileSync(path, "utf8");
        for(const banned of BANNED_SUBSTRINGS) {
          expect(source.includes(banned)).toBe(false);
        }
      });
    }
  }
});
