import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const fail = (message: string): never => { throw new Error(`type mapping check: ${message}`); };

export const readSpec = (path: string): string => readFileSync(join(root, path), "utf8");

/** The four mapping-table cells of one table row, without the pipes. */
export const rowCells = (line: string): string[] => line.split("|").map((cell) => cell.trim()).slice(1, -1);

/** Checks the `Int` row of the features/14 fixed mapping table. */
export const checkIntRow = (mapping: string): void => {
  const row = mapping.split("\n").find((line) => line.startsWith("| `Int` |"));
  if (row === undefined) fail("features/14: the mapping table has no `Int` row");
  const cells = rowCells(row);
  if (cells.length !== 4) fail(`features/14: the Int row has ${cells.length} cells, expected 4`);
  if (cells[1] !== "`u32` (`i32` inside resident runtime modules)")
    fail(`features/14: the Int row Rust cell is ${JSON.stringify(cells[1])}`);
  if (cells[2] !== "`number`") fail(`features/14: the Int row TypeScript cell is ${JSON.stringify(cells[2])}`);
  if (cells[3] !== "`Int` (`Long` when the declared range exceeds `0x7FFFFFFF`)")
    fail(`features/14: the Int row Kotlin cell is ${JSON.stringify(cells[3])}`);
};

export const checkFragment = (label: string, haystack: string, needle: string): void => {
  if (!haystack.includes(needle)) fail(`${label}: missing the fragment ${JSON.stringify(needle)}`);
};

/** One resident-domain statement: both fragments must appear in the file. */
export const checkResidentStatement = (label: string, text: string, residentNeedle: string, businessNeedle: string): void => {
  checkFragment(label, text, residentNeedle);
  checkFragment(label, text, businessNeedle);
};

export const checkAll = (files: {
  mapping: string;
  numeric: string;
  sortedTables: string;
  unicodeAccess: string;
  graphemes: string;
}): void => {
  checkIntRow(files.mapping);
  checkFragment("features/07", files.numeric,
    "Code points are represented as `Int` in Haxe, `u32` in Rust, `number` in TypeScript, and `Int` in Kotlin.");
  checkFragment("features/07", files.numeric, "`WireU32Be` maps to `Int`, `u32`, `number`, and `Int`");
  checkFragment("features/07", files.numeric, "Haxe `Int` maps to `Int32`");
  checkResidentStatement("stdlib/07", files.sortedTables, "resident `i32` domain", "business unsigned domain");
  checkResidentStatement("stdlib/10", files.unicodeAccess,
    "haxe Int as i32 with byte cursors", "while business modules render u32");
  checkResidentStatement("stdlib/11", files.graphemes,
    "haxe Int as i32 because the clamping contracts carry negative values", "while business modules render u32");
};

if (import.meta.main) {
  checkAll({
    mapping: readSpec("docs/specs/features/14-type-system-mapping.md"),
    numeric: readSpec("docs/specs/features/07-numeric-tower.md"),
    sortedTables: readSpec("docs/specs/stdlib/07-sorted-keyed-tables.md"),
    unicodeAccess: readSpec("docs/specs/stdlib/10-unicode-string-access.md"),
    graphemes: readSpec("docs/specs/stdlib/11-grapheme-clusters.md"),
  });
  console.log("type mapping check: ok");
}
