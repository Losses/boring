import { describe, expect, test } from "bun:test";

/**
 * Structure guard for docs/specs/features/06-errors-and-results.md: codec
 * code throws typed exceptions carrying a variant, so a bare `new Error(` in
 * reference/ts/src or a bare `new haxe.Exception(` in samples/boring is a violation whatever
 * its message says. Tests may construct plain Error values; this scan binds
 * only the source trees.
 */

const TS_SOURCE_DIR = import.meta.dir + "/../../reference/ts/src";
const HAXE_SOURCE_DIR = import.meta.dir + "/../../samples/boring";

async function listFiles(directory: string): Promise<string[]> {
  const names: string[] = [];
  for await (const entry of new Bun.Glob("*.ts").scan({ cwd: directory })) {
    names.push(`${directory}/${entry}`);
  }
  for await (const entry of new Bun.Glob("*.hx").scan({ cwd: directory })) {
    names.push(`${directory}/${entry}`);
  }
  return names;
}

async function readAll(paths: string[]): Promise<string[]> {
  const contents: string[] = [];
  for (const path of paths) {
    contents.push(await Bun.file(path).text());
  }
  return contents;
}

describe("typed error structure", () => {
  test("reference/ts/src contains no bare Error construction", async () => {
    const files = await listFiles(TS_SOURCE_DIR);
    const contents = await readAll(files);
    const offenders: string[] = [];
    for (let i = 0; i < files.length; i += 1) {
      if (contents[i]!.includes("new Error(")) {
        offenders.push(files[i]!);
      }
    }
    expect(offenders).toEqual([]);
  });

  test("samples/boring contains no bare haxe.Exception construction", async () => {
    const files = await listFiles(HAXE_SOURCE_DIR);
    const contents = await readAll(files);
    const offenders: string[] = [];
    for (let i = 0; i < files.length; i += 1) {
      if (contents[i]!.includes("new haxe.Exception(")) {
        offenders.push(files[i]!);
      }
    }
    expect(offenders).toEqual([]);
  });
});
