/**
 * Re-validates the committed grapheme break table against the official
 * Unicode conformance file (docs/specs/stdlib/11-grapheme-clusters.md).
 * The generator enforces the same gate before writing the table; this
 * test makes a stale or hand-edited table fail the ordinary test run.
 */

import { readFileSync } from "node:fs";
import { describe, expect, test } from "bun:test";
import { runConformance } from "../../tools/grapheme-table-lib";

const REPO_ROOT = import.meta.dir + "/../..";
const DATA_PATH = `${REPO_ROOT}/tools/unicode-data/GraphemeBreakTest-17.0.0.txt`;
const TABLE_PATH = `${REPO_ROOT}/src/reflaxe/unicode/GraphemeBreakData.hx`;

function readCommittedTable(): number[] {
	const source = readFileSync(TABLE_PATH, "utf8");
	const body = source.split("public static final TABLE:Array<Int> = [")[1];
	if (body === undefined) {
		throw new Error("table array not found in GraphemeBreakData.hx");
	}
	const closing = body.indexOf("];");
	if (closing === -1) {
		throw new Error("table array is not terminated in GraphemeBreakData.hx");
	}
	return body
		.slice(0, closing)
		.split(",")
		.map((value) => value.trim())
		.filter((value) => value.length > 0)
		.map((value) => Number(value));
}

describe("grapheme break data", () => {
	test("committed table passes the Unicode conformance vectors", () => {
		const table = readCommittedTable();
		expect(table.length % 3).toBe(0);
		const failures = runConformance(table, readFileSync(DATA_PATH, "utf8"));
		expect(failures).toEqual([]);
	});
});
